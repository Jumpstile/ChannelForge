use serde::{Deserialize, Serialize};
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
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum PickerErrorCode {
    PickerUnavailable,
    PermissionDenied,
    WrongKind,
    Unknown,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupSelectionResult {
    pub kind: SetupSelectionKind,
    pub outcome: SetupSelectionOutcome,
    pub selection_status: SelectionStatus,
    pub validation_status: ValidationStatus,
    pub error_code: Option<PickerErrorCode>,
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

// Native rfd returns cancellation as `None`; fake adapters cover bounded error mapping.
#[allow(dead_code)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum PickerError {
    Unavailable,
    PermissionDenied,
    Unknown,
}

trait PickerAdapter: Send + Sync {
    fn pick(&self, kind: SetupSelectionKind) -> Result<Option<PickerSelectionKind>, PickerError>;
}

struct NativePicker<'a> {
    window: &'a Window,
}

impl PickerAdapter for NativePicker<'_> {
    fn pick(&self, kind: SetupSelectionKind) -> Result<Option<PickerSelectionKind>, PickerError> {
        let selection = match kind {
            SetupSelectionKind::Workspace => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose workspace")
                .pick_folder()
                .map(|_| PickerSelectionKind::Workspace),
            SetupSelectionKind::Playlist => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose playlist")
                .add_filter("Playlist", &["m3u", "m3u8"])
                .pick_file()
                .map(|_| PickerSelectionKind::File),
            SetupSelectionKind::Guide => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose guide")
                .add_filter("Guide", &["xml", "xmltv", "gz", "zip"])
                .pick_file()
                .map(|_| PickerSelectionKind::File),
        };

        Ok(selection)
    }
}

fn selected_result(kind: SetupSelectionKind) -> SetupSelectionResult {
    SetupSelectionResult {
        kind,
        outcome: SetupSelectionOutcome::Selected,
        selection_status: SelectionStatus::Selected,
        validation_status: ValidationStatus::NotChecked,
        error_code: None,
    }
}

fn cancelled_result(kind: SetupSelectionKind) -> SetupSelectionResult {
    SetupSelectionResult {
        kind,
        outcome: SetupSelectionOutcome::Cancelled,
        selection_status: SelectionStatus::NotSelected,
        validation_status: ValidationStatus::NotChecked,
        error_code: None,
    }
}

fn error_result(
    kind: SetupSelectionKind,
    outcome: SetupSelectionOutcome,
    error_code: PickerErrorCode,
) -> SetupSelectionResult {
    SetupSelectionResult {
        kind,
        outcome,
        selection_status: SelectionStatus::NotSelected,
        validation_status: ValidationStatus::NotChecked,
        error_code: Some(error_code),
    }
}

fn choose_setup_item_with_adapter(
    kind: SetupSelectionKind,
    adapter: &dyn PickerAdapter,
) -> SetupSelectionResult {
    match adapter.pick(kind) {
        Ok(Some(selection)) if selection.matches(kind) => selected_result(kind),
        Ok(Some(_)) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerErrorCode::WrongKind,
        ),
        Ok(None) => cancelled_result(kind),
        Err(PickerError::Unavailable) => error_result(
            kind,
            SetupSelectionOutcome::Unavailable,
            PickerErrorCode::PickerUnavailable,
        ),
        Err(PickerError::PermissionDenied) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerErrorCode::PermissionDenied,
        ),
        Err(PickerError::Unknown) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerErrorCode::Unknown,
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
        result: Result<Option<PickerSelectionKind>, PickerError>,
    }

    impl PickerAdapter for FakePicker {
        fn pick(
            &self,
            _kind: SetupSelectionKind,
        ) -> Result<Option<PickerSelectionKind>, PickerError> {
            self.result
        }
    }

    #[test]
    fn accepts_workspace_playlist_and_guide_without_returning_native_values() {
        let cases = [
            (
                SetupSelectionKind::Workspace,
                PickerSelectionKind::Workspace,
            ),
            (SetupSelectionKind::Playlist, PickerSelectionKind::File),
            (SetupSelectionKind::Guide, PickerSelectionKind::File),
        ];

        for (kind, selection) in cases {
            let result = choose_setup_item_with_adapter(
                kind,
                &FakePicker {
                    result: Ok(Some(selection)),
                },
            );

            assert_eq!(result, selected_result(kind));
            assert!(!format!("{result:?}").contains("path"));
            assert!(!format!("{result:?}").contains("filename"));
        }
    }

    #[test]
    fn serializes_only_safe_selection_fields() {
        let serialized = serde_json::to_value(selected_result(SetupSelectionKind::Playlist))
            .expect("selection result should serialize");

        assert_eq!(serialized["kind"], "playlist");
        assert_eq!(serialized["outcome"], "selected");
        assert_eq!(serialized["selectionStatus"], "selected");
        assert_eq!(serialized["validationStatus"], "not-checked");
        assert!(serialized.get("path").is_none());
        assert!(serialized.get("filename").is_none());
        assert!(serialized.get("contents").is_none());
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
                result: Ok(Some(PickerSelectionKind::File)),
            },
        );

        assert_eq!(
            result,
            error_result(
                SetupSelectionKind::Workspace,
                SetupSelectionOutcome::Rejected,
                PickerErrorCode::WrongKind,
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
                PickerErrorCode::PickerUnavailable,
            ),
            (
                PickerError::PermissionDenied,
                SetupSelectionOutcome::Rejected,
                PickerErrorCode::PermissionDenied,
            ),
            (
                PickerError::Unknown,
                SetupSelectionOutcome::Rejected,
                PickerErrorCode::Unknown,
            ),
        ];

        for (error, outcome, code) in cases {
            let result = choose_setup_item_with_adapter(
                SetupSelectionKind::Guide,
                &FakePicker { result: Err(error) },
            );

            assert_eq!(
                result,
                error_result(SetupSelectionKind::Guide, outcome, code)
            );
        }
    }
}
