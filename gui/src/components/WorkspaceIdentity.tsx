import type { WorkspaceIdentityValue } from '../app/workspaceIdentity'

export function WorkspaceIdentity({ identity }: { identity: WorkspaceIdentityValue }) {
  return (
    <div className="workspace-identity" aria-label={`Workspace ${identity.label}`}>
      <span className="workspace-identity-label">Workspace</span>
      <span className="workspace-identity-name">{identity.label}</span>
      <span className="workspace-identity-digest" title="Safe workspace identity placeholder">{identity.digest}</span>
    </div>
  )
}
