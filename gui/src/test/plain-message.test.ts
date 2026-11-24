import { describe, expect, it } from 'vitest'
import { plainMessageSummary } from '../app/plainMessage'

describe('plainMessageSummary', () => {
  it('keeps a plain sentence as it is', () => {
    expect(plainMessageSummary('The playlist is not available right now.')).toBe('The playlist is not available right now.')
  })

  it('collapses whitespace and strips control characters', () => {
    expect(plainMessageSummary('Not   ready\u0007\n yet.')).toBe('Not ready yet.')
  })

  it('cuts a long message at a word boundary and adds dots', () => {
    const result = plainMessageSummary('The playlist server is busy and cannot build this lineup right now because many other requests are waiting in line ahead of it today.')
    expect(result).toBe('The playlist server is busy and cannot build this lineup right now because many other requests are waiting in line ahead...')
    expect(result!.length).toBeLessThanOrEqual(123)
  })

  it.each([
    ['empty', ''],
    ['only spaces', '   '],
    ['JSON object', '{"error":"not available"}'],
    ['JSON array', '["not available"]'],
    ['markup', '<html>Bad gateway</html>'],
    ['stack trace', 'Error: boom\n    at run (main.js:10:5)'],
    ['exception word', 'System.InvalidOperationException happened'],
    ['at line', 'Parse failed at line 4'],
    ['Windows path', 'Cannot read C:\\Data\\lineup.json'],
    ['Unix path', 'Cannot read /var/lib/app/lineup.json'],
    ['URL', 'Could not reach http://localhost:8080/api'],
    ['hex run', 'Request 3f9a7c21d4b8e5f0 failed'],
    ['mostly symbols', '#### !!! ??? 404 ~~~ 500 ###'],
  ])('falls back for %s', (_name, raw) => {
    expect(plainMessageSummary(raw)).toBeNull()
  })

  it('returns null for undefined', () => {
    expect(plainMessageSummary(undefined)).toBeNull()
  })
})
