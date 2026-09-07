export type WorkflowStep = {
  number: number
  label: string
  state: 'current' | 'upcoming' | 'complete'
}

export function StepRail({ steps }: { steps: WorkflowStep[] }) {
  return (
    <ol className="step-rail" aria-label="Guided workflow progress">
      {steps.map((step) => (
        <li className={`step-rail-item step-${step.state}`} key={step.label}>
          <span className="step-number" aria-hidden="true">{step.number}</span>
          <span>{step.label}</span>
        </li>
      ))}
    </ol>
  )
}
