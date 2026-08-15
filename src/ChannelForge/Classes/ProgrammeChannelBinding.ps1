class ProgrammeChannelBinding {
    [string]$SourceId
    [string]$ChannelReference
    [string]$BindingKey
    [string]$BindingKind

    ProgrammeChannelBinding() {
        $this.SourceId = ''
        $this.ChannelReference = ''
        $this.BindingKey = ''
        $this.BindingKind = 'SourceScoped'
    }
}
