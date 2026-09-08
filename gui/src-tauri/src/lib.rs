use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{self, BufRead, BufReader},
    path::Path,
};
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
#[serde(rename_all = "kebab-case")]
pub enum PlaylistContentStatus {
    NotChecked,
    Checking,
    Checked,
    NeedsAttention,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum PlaylistContentReasonCode {
    MissingHeader,
    EmptyPlaylist,
    IncompleteEntry,
    OrphanStreamLine,
    InvalidEncoding,
    TooLarge,
    Unreadable,
    CheckUnavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistContentSummary {
    pub content_status: PlaylistContentStatus,
    pub entry_count: Option<u64>,
    pub reason_code: Option<PlaylistContentReasonCode>,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupSelectionResult {
    pub kind: SetupSelectionKind,
    pub outcome: SetupSelectionOutcome,
    pub selection_status: SelectionStatus,
    pub validation_status: ValidationStatus,
    pub reason_code: Option<PickerReasonCode>,
    #[serde(rename = "playlistContent", skip_serializing_if = "Option::is_none")]
    pub playlist_content: Option<PlaylistContentSummary>,
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
    playlist_content: Option<PlaylistContentSummary>,
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
                    playlist_content: None,
                }),
            SetupSelectionKind::Playlist => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose playlist")
                .add_filter("Playlist", &["m3u", "m3u8"])
                .pick_file()
                .map(|path| {
                    let pre_parse_check = check_file(&path);
                    let content = if pre_parse_check == PreParseCheck::ReadyToInspect {
                        Some(inspect_playlist_content(&path))
                    } else {
                        None
                    };
                    PickerSelection {
                        kind: PickerSelectionKind::File,
                        pre_parse_check,
                        playlist_content: content,
                    }
                }),
            SetupSelectionKind::Guide => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose guide")
                .add_filter("Guide", &["xml", "xmltv", "gz", "zip"])
                .pick_file()
                .map(|path| PickerSelection {
                    kind: PickerSelectionKind::File,
                    pre_parse_check: check_file(&path),
                    playlist_content: None,
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

const MAX_PLAYLIST_BYTES: u64 = 64 * 1024 * 1024;
const MAX_LOGICAL_LINE_BYTES: usize = 1024 * 1024;

fn inspect_playlist_content(path: &Path) -> PlaylistContentSummary {
    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) => {
            return content_failure(if error.kind() == io::ErrorKind::PermissionDenied {
                PlaylistContentReasonCode::Unreadable
            } else {
                PlaylistContentReasonCode::CheckUnavailable
            })
        }
    };

    if metadata.len() > MAX_PLAYLIST_BYTES {
        return content_failure(PlaylistContentReasonCode::TooLarge);
    }

    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(error) => {
            return content_failure(if error.kind() == io::ErrorKind::PermissionDenied {
                PlaylistContentReasonCode::Unreadable
            } else {
                PlaylistContentReasonCode::CheckUnavailable
            })
        }
    };

    match inspect_playlist_reader(BufReader::new(file)) {
        Ok(entry_count) => PlaylistContentSummary {
            content_status: PlaylistContentStatus::Checked,
            entry_count: Some(entry_count),
            reason_code: None,
        },
        Err(reason_code) => content_failure(reason_code),
    }
}

fn inspect_playlist_reader<R: BufRead>(mut reader: R) -> Result<u64, PlaylistContentReasonCode> {
    let mut line = Vec::new();
    let mut total_bytes = 0_u64;
    let mut first_physical_line = true;
    let mut saw_non_empty_line = false;
    let mut saw_header = false;
    let mut pending_entry = false;
    let mut entry_count = 0_u64;

    loop {
        line.clear();
        let bytes_read = reader
            .read_until(b'\n', &mut line)
            .map_err(content_io_reason)?;
        if bytes_read == 0 {
            break;
        }

        total_bytes = total_bytes.saturating_add(bytes_read as u64);
        if total_bytes > MAX_PLAYLIST_BYTES {
            return Err(PlaylistContentReasonCode::TooLarge);
        }

        let mut logical_length = line.len();
        if line.ends_with(b"\n") {
            logical_length -= 1;
        }
        if logical_length > 0 && line[logical_length - 1] == b'\r' {
            logical_length -= 1;
        }
        if logical_length > MAX_LOGICAL_LINE_BYTES {
            return Err(PlaylistContentReasonCode::TooLarge);
        }

        let mut text =
            std::str::from_utf8(&line).map_err(|_| PlaylistContentReasonCode::InvalidEncoding)?;
        if first_physical_line {
            text = text.strip_prefix('\u{feff}').unwrap_or(text);
            first_physical_line = false;
        }
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        saw_non_empty_line = true;

        if !saw_header {
            if trimmed != "#EXTM3U" {
                return Err(PlaylistContentReasonCode::MissingHeader);
            }
            saw_header = true;
            continue;
        }

        let is_extinf = trimmed
            .as_bytes()
            .get(..8)
            .map_or(false, |prefix| prefix.eq_ignore_ascii_case(b"#EXTINF:"));
        if is_extinf {
            if pending_entry {
                return Err(PlaylistContentReasonCode::IncompleteEntry);
            }
            pending_entry = true;
            continue;
        }

        if trimmed.starts_with('#') {
            continue;
        }

        if !pending_entry {
            return Err(PlaylistContentReasonCode::OrphanStreamLine);
        }

        pending_entry = false;
        entry_count = entry_count.saturating_add(1);
    }

    if !saw_non_empty_line {
        return Err(PlaylistContentReasonCode::EmptyPlaylist);
    }
    if !saw_header {
        return Err(PlaylistContentReasonCode::MissingHeader);
    }
    if pending_entry {
        return Err(PlaylistContentReasonCode::IncompleteEntry);
    }
    if entry_count == 0 {
        return Err(PlaylistContentReasonCode::EmptyPlaylist);
    }

    Ok(entry_count)
}

fn content_io_reason(error: io::Error) -> PlaylistContentReasonCode {
    if error.kind() == io::ErrorKind::PermissionDenied {
        PlaylistContentReasonCode::Unreadable
    } else {
        PlaylistContentReasonCode::CheckUnavailable
    }
}

fn content_failure(reason_code: PlaylistContentReasonCode) -> PlaylistContentSummary {
    PlaylistContentSummary {
        content_status: PlaylistContentStatus::NeedsAttention,
        entry_count: None,
        reason_code: Some(reason_code),
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
    playlist_content: Option<PlaylistContentSummary>,
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
        playlist_content: if kind == SetupSelectionKind::Playlist {
            playlist_content
        } else {
            None
        },
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
        playlist_content: None,
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
        playlist_content: None,
    }
}

fn choose_setup_item_with_adapter(
    kind: SetupSelectionKind,
    adapter: &dyn PickerAdapter,
) -> SetupSelectionResult {
    match adapter.pick(kind) {
        Ok(Some(selection)) if selection.kind.matches(kind) => {
            selected_result(kind, selection.pre_parse_check, selection.playlist_content)
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
            playlist_content: None,
        }
    }

    fn scan(content: &str) -> Result<u64, PlaylistContentReasonCode> {
        inspect_playlist_reader(std::io::Cursor::new(content.as_bytes()))
    }

    #[test]
    fn scans_complete_m3u_entries_without_retaining_content() {
        let entries = scan("#EXTM3U\n#EXTINF:-1,One\nhttps://secret.example/one\n#EXTINF:-1,Two\nhttps://secret.example/two\n")
            .expect("valid playlist should scan");

        assert_eq!(entries, 2);
    }

    #[test]
    fn accepts_bom_comments_and_blank_lines() {
        let entries = scan("\u{feff}#EXTM3U\n\n#EXT-X-VERSION:3\n#EXTINF:-1,One\nopaque-stream\n")
            .expect("valid playlist should scan");

        assert_eq!(entries, 1);
    }

    #[test]
    fn maps_structural_failures_to_safe_reasons() {
        let cases = [
            ("", PlaylistContentReasonCode::EmptyPlaylist),
            (
                "#EXTINF:-1,One\nopaque-stream\n",
                PlaylistContentReasonCode::MissingHeader,
            ),
            (
                "#EXTM3U\n#EXTINF:-1,One\n",
                PlaylistContentReasonCode::IncompleteEntry,
            ),
            (
                "#EXTM3U\nopaque-stream\n",
                PlaylistContentReasonCode::OrphanStreamLine,
            ),
            (
                "#EXTM3U\n#EXTINF:-1,One\n#EXTINF:-1,Two\nopaque-stream\n",
                PlaylistContentReasonCode::IncompleteEntry,
            ),
        ];

        for (content, reason_code) in cases {
            assert_eq!(scan(content), Err(reason_code));
        }
    }

    #[test]
    fn rejects_invalid_encoding_and_oversized_lines() {
        let invalid = inspect_playlist_reader(std::io::Cursor::new(vec![
            b'#', b'E', b'X', b'T', b'M', b'3', b'U', b'\n', 0xff,
        ]));
        assert_eq!(invalid, Err(PlaylistContentReasonCode::InvalidEncoding));

        let mut oversized = String::from("#EXTM3U\n#EXTINF:-1,One\n");
        oversized.push_str(&"x".repeat(MAX_LOGICAL_LINE_BYTES + 1));
        oversized.push('\n');
        assert_eq!(scan(&oversized), Err(PlaylistContentReasonCode::TooLarge));
    }

    #[test]
    fn serializes_content_summary_without_native_or_raw_values() {
        let summary = PlaylistContentSummary {
            content_status: PlaylistContentStatus::Checked,
            entry_count: Some(2),
            reason_code: None,
        };
        let serialized = serde_json::to_value(summary).expect("summary should serialize");

        assert_eq!(serialized["contentStatus"], "checked");
        assert_eq!(serialized["entryCount"], 2);
        assert!(serialized.get("path").is_none());
        assert!(serialized.get("filename").is_none());
        assert!(serialized.get("url").is_none());
        assert!(serialized.get("contents").is_none());
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

            assert_eq!(
                result,
                selected_result(kind, PreParseCheck::ReadyToInspect, None)
            );
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
                        playlist_content: None,
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
            Some(PlaylistContentSummary {
                content_status: PlaylistContentStatus::Checked,
                entry_count: Some(2),
                reason_code: None,
            }),
        ))
        .expect("selection result should serialize");

        assert_eq!(serialized["kind"], "playlist");
        assert_eq!(serialized["outcome"], "selected");
        assert_eq!(serialized["selectionStatus"], "selected");
        assert_eq!(serialized["validationStatus"], "ready-to-inspect");
        assert!(serialized["reasonCode"].is_null());
        assert!(serialized["playlistContent"]["reasonCode"].is_null());
        assert_eq!(serialized["playlistContent"]["contentStatus"], "checked");
        assert_eq!(serialized["playlistContent"]["entryCount"], 2);
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
