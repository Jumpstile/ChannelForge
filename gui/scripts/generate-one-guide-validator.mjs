import { readFile, writeFile } from 'node:fs/promises'
import Ajv2020 from 'ajv/dist/2020.js'
import { _ } from 'ajv'
import standaloneCode from 'ajv/dist/standalone/index.js'
import addFormats from 'ajv-formats'
import { compile } from 'json-schema-to-typescript'

const schemaUrl = new URL('../../schemas/one-guide-projection.schema.json', import.meta.url)
const moduleUrl = new URL('../src/app/oneGuideProjectionValidator.generated.js', import.meta.url)
const typesUrl = new URL('../src/app/oneGuideProjection.generated.ts', import.meta.url)
const declarationUrl = new URL('../src/app/oneGuideProjectionValidator.generated.d.ts', import.meta.url)
const schema = JSON.parse(await readFile(schemaUrl, 'utf8'))
const typeSource = await compile(schema, 'OneGuideProjection', {
  bannerComment: '// Generated from schemas/one-guide-projection.schema.json. Do not edit.',
  style: { singleQuote: true, semi: false },
})
const ajv = new Ajv2020({ code: { source: true, esm: true, lines: true, formats: _`formats.fullFormats` } })
addFormats(ajv)
const validate = ajv.compile(schema)
const code = standaloneCode(ajv, validate).replace(/^"use strict";\s*/, '')
const runtimeModules = new Map()
const cspSafeCode = code.replace(/require\("([^"]+)"\)\.default/g, (_match, modulePath) => {
  if (!runtimeModules.has(modulePath)) runtimeModules.set(modulePath, `ajvRuntime${runtimeModules.size}`)
  return runtimeModules.get(modulePath)
})
if (/\brequire\s*\(|\bnew\s+Function\b|\beval\s*\(/.test(cspSafeCode)) {
  throw new Error('Ajv standalone output contains dynamic module loading or evaluation.')
}
const runtimeImports = [...runtimeModules].flatMap(([modulePath, name]) => {
  const specifier = modulePath.endsWith('.js') ? modulePath : `${modulePath}.js`
  return [
    `import { default as ${name}Module } from '${specifier}'`,
    `const ${name} = ${name}Module.default ?? ${name}Module`,
  ]
})
const generatedModule = [
  '// Generated from schemas/one-guide-projection.schema.json. Do not edit.',
  "import * as formatsModule from 'ajv-formats/dist/formats.js'",
  'const formats = formatsModule.default ?? formatsModule',
  ...runtimeImports,
  cspSafeCode,
  '',
].join('\n')
const generatedTypes = [
  typeSource.trimEnd(),
  'export type OneGuidePage = ChannelForgeOneGuideReadProjection',
  "export type OneGuideItem = OneGuidePage['Items'][number]",
  "export type OneGuideOffering = OneGuideItem['Offerings'][number]",
  "export type OneGuideCategory = NonNullable<OneGuidePage['CategoryKey']>",
  '',
].join('\n')
const generatedDeclaration = [
  '// Generated from schemas/one-guide-projection.schema.json. Do not edit.',
  "import type { OneGuidePage } from './oneGuideProjection.generated.js'",
  'declare const validateOneGuideProjection: (data: unknown) => data is OneGuidePage',
  'export default validateOneGuideProjection',
  '',
].join('\n')

const normalizeLineEndings = (text) => text.replace(/\r\n/g, '\n')
for (const [url, expected] of [[typesUrl, generatedTypes], [moduleUrl, generatedModule], [declarationUrl, generatedDeclaration]]) {
  if (process.argv.includes('--check')) {
    let actual
    try {
      actual = await readFile(url, 'utf8')
    } catch {
      throw new Error(`Generated One Guide types or validator is missing: ${url.pathname}`)
    }
    if (normalizeLineEndings(actual) !== expected) throw new Error(`Generated One Guide types or validator is stale: ${url.pathname}`)
  } else {
    await writeFile(url, expected, 'utf8')
  }
}

console.log(process.argv.includes('--check') ? 'One Guide types and validator are current.' : 'Generated One Guide types and CSP-safe validator.')
