const termHelp: Record<string, string> = {
  'Candidate lineup': 'A proposed lineup. It is not accepted and cannot replace your current lineup by itself.',
  Source: 'One playlist or guide input from a provider or local file.',
  'Last-known-good': 'The most recent validated result preserved when a later refresh fails.',
}

export function TermCoach({ term }: { term: keyof typeof termHelp }) {
  return (
    <span className="term-coach">
      <span>{term}</span>
      <span className="term-coach-help">{termHelp[term]}</span>
    </span>
  )
}
