export function HttpWarning() {
  return (
    <p className="auth-warning" role="note">
      <strong>Warning:</strong> you opened ChannelForge over plain HTTP from another computer. Anyone on your network could read the password you type. Ask the person who runs the server to set up HTTPS.
    </p>
  )
}
