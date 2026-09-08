use serde::{Deserialize, Serialize};
use std::{fs, io, path::Path};
use tauri::Window;

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SetupSelectionKind {
    Workspace,
    Playlist,
    Guide,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum SetupSelectionOutcome {
    Selected,
    Cancelled,
    Rejected,
    Unavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum SelectionStatus {
    Selected,
    NotSelected,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ValidationStatus {
    NotChecked,
    Checking,
    ReadyToInspect,
    NeedsAttention,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum PickerReasonCode {
    PickerUnavailable,
    PermissionDenied,
    WrongKind,
    Unknown,
    NotFound,
    NotReadable,
    CheckUnavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupSelectionResult {
    pub kind: SetupSelectionKind,
    pub outcome: SetupSelectionOutcome,
    pub selection_status: SelectionStatus,
    pub validation_status: ValidationStatus,
    pub reason_code: Option<PickerReasonCode>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum PickerSelectionKind {
    Workspace,
    File,
}

impl PickerSelectionKind {
    fn matches(self, kind: SetupSelectionKind) -> bool {
        matches!(
            (kind, self),
            (
                SetupSelectionKind::Workspace,
                PickerSelectionKind::Workspace
            ) | (SetupSelectionKind::Playlist, PickerSelectionKind::File)
                | (SetupSelectionKind::Guide, PickerSelectionKind::File)
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum PreParseReason {
    NotFound,
    WrongKind,
    NotReadable,
    CheckUnavailable,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum PreParseCheck {
    ReadyToInspect,
    NeedsAttention(PreParseReason),
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct PickerSelection {
    kind: PickerSelectionKind,
    pre_parse_check: PreParseCheck,
}

// Native rfd returns cancellation as `None`; fake adapters cover bounded error mapping.
#[allow(dead_code)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum PickerError {
    Unavailable,
    PermissionDenied,
    Unknown,
}

trait PickerAdapter: Send + Sync {
    fn pick(&self, kind: SetupSelectionKind) -> Result<Option<PickerSelection>, PickerError>;
}

struct NativePicker<'a> {
    window: &'a Window,
}

impl PickerAdapter for NativePicker<'_> {
    fn pick(&self, kind: SetupSelectionKind) -> Result<Option<PickerSelection>, PickerError> {
        let selection = match kind {
            SetupSelectionKind::Workspace => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose workspace")
                .pick_folder()
                .map(|path| PickerSelection {
                    kind: PickerSelectionKind::Workspace,
                    pre_parse_check: check_directory(&path),
                }),
            SetupSelectionKind::Playlist => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose playlist")
                .add_filter("Playlist", &["m3u", "m3u8"])
                .pick_file()
                .map(|path| PickerSelection {
                    kind: PickerSelectionKind::File,
                    pre_parse_check: check_file(&path),
                }),
            SetupSelectionKind::Guide => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose guide")
                .add_filter("Guide", &["xml", "xmltv", "gz", "zip"])
                .pick_file()
                .map(|path| PickerSelection {
                    kind: PickerSelectionKind::File,
                    pre_parse_check: check_file(&path),
                }),
        };

        Ok(selection)
    }
}

fn check_directory(path: &Path) -> PreParseCheck {
    match fs::metadata(path) {
        Ok(metadata) if !metadata.is_dir() => {
            PreParseCheck::NeedsAttention(PreParseReason::WrongKind)
        }
        Ok(_) => match fs::read_dir(path) {
            Ok(_) => PreParseCheck::ReadyToInspect,
            Err(error) => PreParseCheck::NeedsAttention(pre_parse_reason(error)),
        },
        Err(error) => PreParseCheck::NeedsAttention(pre_parse_reason(error)),
    }
}

fn check_file(path: &Path) -> PreParseCheck {
    match fs::metadata(path) {
        Ok(metadata) if !metadata.is_file() => {
            PreParseCheck::NeedsAttention(PreParseReason::WrongKind)
        }
        Ok(_) => match fs::File::open(path) {
            Ok(_) => PreParseCheck::ReadyToInspect,
            Err(error) => PreParseCheck::NeedsAttention(pre_parse_reason(error)),
        },
        Err(error) => PreParseCheck::NeedsAttention(pre_parse_reason(error)),
    }
}

fn pre_parse_reason(error: io::Error) -> PreParseReason {
    match error.kind() {
        io::ErrorKind::NotFound => PreParseReason::NotFound,
        io::ErrorKind::PermissionDenied => PreParseReason::NotReadable,
        _ => PreParseReason::CheckUnavailable,
    }
}

fn selected_result(
    kind: SetupSelectionKind,
    pre_parse_check: PreParseCheck,
) -> SetupSelectionResult {
    let (validation_status, reason_code) = match pre_parse_check {
        PreParseCheck::ReadyToInspect => (ValidationStatus::ReadyToInspect, None),
        PreParseCheck::NeedsAttention(reason) => (
            ValidationStatus::NeedsAttention,
            Some(pre_parse_reason_code(reason)),
        ),
    };

    SetupSelectionResult {
        kind,
        outcome: SetupSelectionOutcome::Selected,
        selection_status: SelectionStatus::Selected,
        validation_status,
        reason_code,
    }
}

fn pre_parse_reason_code(reason: PreParseReason) -> PickerReasonCode {
    match reason {
        PreParseReason::NotFound => PickerReasonCode::NotFound,
        PreParseReason::WrongKind => PickerReasonCode::WrongKind,
        PreParseReason::NotReadable => PickerReasonCode::NotReadable,
        PreParseReason::CheckUnavailable => PickerReasonCode::CheckUnavailable,
    }
}

fn cancelled_result(kind: SetupSelectionKind) -> SetupSelectionResult {
    SetupSelectionResult {
        kind,
        outcome: SetupSelectionOutcome::Cancelled,
        selection_status: SelectionStatus::NotSelected,
        validation_status: ValidationStatus::NotChecked,
        reason_code: None,
    }
}

fn error_result(
    kind: SetupSelectionKind,
    outcome: SetupSelectionOutcome,
    reason_code: PickerReasonCode,
) -> SetupSelectionResult {
    SetupSelectionResult {
        kind,
        outcome,
        selection_status: SelectionStatus::NotSelected,
        validation_status: ValidationStatus::NotChecked,
        reason_code: Some(reason_code),
    }
}

fn choose_setup_item_with_adapter(
    kind: SetupSelectionKind,
    adapter: &dyn PickerAdapter,
) -> SetupSelectionResult {
    match adapter.pick(kind) {
        Ok(Some(selection)) if selection.kind.matches(kind) => {
            selected_result(kind, selection.pre_parse_check)
        }
        Ok(Some(_)) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerReasonCode::WrongKind,
        ),
        Ok(None) => cancelled_result(kind),
        Err(PickerError::Unavailable) => error_result(
            kind,
            SetupSelectionOutcome::Unavailable,
            PickerReasonCode::PickerUnavailable,
        ),
        Err(PickerError::PermissionDenied) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerReasonCode::PermissionDenied,
        ),
        Err(PickerError::Unknown) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerReasonCode::Unknown,
        ),
    }
}

mod command {
    use super::*;

    #[tauri::command]
    pub async fn choose_setup_item(
        kind: SetupSelectionKind,
        window: Window,
    ) -> SetupSelectionResult {
        choose_setup_item_with_adapter(kind, &NativePicker { window: &window })
    }
}

pub use command::choose_setup_item;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![command::choose_setup_item])
        .run(tauri::generate_context!())
        .expect("error while running ChannelForge");
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakePicker {
        result: Result<Option<PickerSelection>, PickerError>,
    }

    impl PickerAdapter for FakePicker {
        fn pick(&self, _kind: SetupSelectionKind) -> Result<Option<PickerSelection>, PickerError> {
            self.result
        }
    }

    fn ready_selection(kind: PickerSelectionKind) -> PickerSelection {
        PickerSelection {
            kind,
            pre_parse_check: PreParseCheck::ReadyToInspect,
        }
    }

    #[test]
    fn accepts_workspace_playlist_and_guide_without_returning_native_values() {
        let cases = [
            (
                SetupSelectionKind::Workspace,
                ready_selection(PickerSelectionKind::Workspace),
            ),
            (
                SetupSelectionKind::Playlist,
                ready_selection(PickerSelectionKind::File),
            ),
            (
                SetupSelectionKind::Guide,
                ready_selection(PickerSelectionKind::File),
            ),
        ];

        for (kind, selection) in cases {
            let result = choose_setup_item_with_adapter(
                kind,
                &FakePicker {
                    result: Ok(Some(selection)),
                },
            );

            assert_eq!(result, selected_result(kind, PreParseCheck::ReadyToInspect));
            assert!(!format!("{result:?}").contains("path"));
            assert!(!format!("{result:?}").contains("filename"));
        }
    }

    #[test]
    fn maps_pre_parse_failures_to_attention_without_exposing_native_values() {
        let cases = [
            (PreParseReason::NotFound, PickerReasonCode::NotFound),
            (PreParseReason::WrongKind, PickerReasonCode::WrongKind),
            (PreParseReason::NotReadable, PickerReasonCode::NotReadable),
            (
                PreParseReason::CheckUnavailable,
                PickerReasonCode::CheckUnavailable,
            ),
        ];

        for (reason, reason_code) in cases {
            let result = choose_setup_item_with_adapter(
                SetupSelectionKind::Playlist,
                &FakePicker {
                    result: Ok(Some(PickerSelection {
                        kind: PickerSelectionKind::File,
                        pre_parse_check: PreParseCheck::NeedsAttention(reason),
                    })),
                },
            );

            assert_eq!(result.outcome, SetupSelectionOutcome::Selected);
            assert_eq!(result.selection_status, SelectionStatus::Selected);
            assert_eq!(result.validation_status, ValidationStatus::NeedsAttention);
            assert_eq!(result.reason_code, Some(reason_code));
            assert!(!format!("{result:?}").contains("path"));
        }
    }

    #[test]
    fn serializes_only_safe_selection_fields() {
        let serialized = serde_json::to_value(selected_result(
            SetupSelectionKind::Playlist,
            PreParseCheck::ReadyToInspect,
        ))
        .expect("selection result should serialize");

        assert_eq!(serialized["kind"], "playlist");
        assert_eq!(serialized["outcome"], "selected");
        assert_eq!(serialized["selectionStatus"], "selected");
        assert_eq!(serialized["validationStatus"], "ready-to-inspect");
        assert!(serialized["reasonCode"].is_null());
        assert!(serialized.get("path").is_none());
        assert!(serialized.get("filename").is_none());
        assert!(serialized.get("contents").is_none());
        assert!(serialized.get("url").is_none());
        assert!(serialized.get("token").is_none());
    }

    #[test]
    fn cancellation_keeps_selection_unselected_and_unchecked() {
        let result = choose_setup_item_with_adapter(
            SetupSelectionKind::Workspace,
            &FakePicker { result: Ok(None) },
        );

        assert_eq!(result, cancelled_result(SetupSelectionKind::Workspace));
    }

    #[test]
    fn rejects_wrong_picker_kind_without_exposing_the_native_selection() {
        let result = choose_setup_item_with_adapter(
            SetupSelectionKind::Workspace,
            &FakePicker {
                result: Ok(Some(ready_selection(PickerSelectionKind::File))),
            },
        );

        assert_eq!(
            result,
            error_result(
                SetupSelectionKind::Workspace,
                SetupSelectionOutcome::Rejected,
                PickerReasonCode::WrongKind,
            )
        );
        assert!(!format!("{result:?}").contains("path"));
    }

    #[test]
    fn maps_picker_errors_to_safe_codes() {
        let cases = [
            (
                PickerError::Unavailable,
                SetupSelectionOutcome::Unavailable,
                PickerReasonCode::PickerUnavailable,
            ),
            (
                PickerError::PermissionDenied,
                SetupSelectionOutcome::Rejected,
                PickerReasonCode::PermissionDenied,
            ),
            (
                PickerError::Unknown,
                SetupSelectionOutcome::Rejected,
                PickerReasonCode::Unknown,
            ),
        ];

        for (error, outcome, reason_code) in cases {
            let result = choose_setup_item_with_adapter(
                SetupSelectionKind::Guide,
                &FakePicker { result: Err(error) },
            );

            assert_eq!(
                result,
                error_result(SetupSelectionKind::Guide, outcome, reason_code)
            );
        }
    }
}
