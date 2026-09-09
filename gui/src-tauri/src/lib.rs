use flate2::read::MultiGzDecoder;
use quick_xml::{events::Event, Reader};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{self, BufRead, BufReader, Read},
    path::{Path, PathBuf},
    process::Command,
    sync::Mutex,
};
use tauri::{State, Window};
use zip::ZipArchive;

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum MatchStatus {
    NotChecked,
    Checking,
    Checked,
    NeedsAttention,
    ReviewNeeded,
    Blocked,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum MatchReasonCode {
    MissingPlaylist,
    MissingGuide,
    PlaylistNotReady,
    GuideNotReady,
    PlaylistContentInvalid,
    GuideContentInvalid,
    PlaylistUnavailable,
    GuideUnavailable,
    UnsupportedFormat,
    TooLarge,
    StaleSelection,
    UnmatchedIdentity,
    AmbiguousIdentity,
    CheckUnavailable,
}
#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistGuideMatchSummary {
    pub match_status: MatchStatus,
    pub playlist_entry_count: Option<u64>,
    pub guide_channel_count: Option<u64>,
    pub matched_count: Option<u64>,
    pub unmatched_playlist_count: Option<u64>,
    pub ambiguous_count: Option<u64>,
    pub guide_only_count: Option<u64>,
    pub requires_review: bool,
    pub reason_code: Option<MatchReasonCode>,
}
#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum SavedLineupPlanStatus {
    NotReady,
    Ready,
    Blocked,
    Stale,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum AcceptedLineupStatus {
    None,
    Present,
    Unavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum CandidateFreshness {
    Current,
    Stale,
    Unknown,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum SavedLineupReasonCode {
    NotEligible,
    StaleCandidate,
    StaleParent,
    NativeUnavailable,
    AcceptanceFailed,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedLineupPlan {
    pub plan_status: SavedLineupPlanStatus,
    pub playlist_entry_count: Option<u64>,
    pub guide_channel_count: Option<u64>,
    pub matched_count: Option<u64>,
    pub unmatched_playlist_count: Option<u64>,
    pub ambiguous_count: Option<u64>,
    pub guide_only_count: Option<u64>,
    pub requires_review: bool,
    pub accepted_lineup_status: AcceptedLineupStatus,
    pub candidate_freshness: CandidateFreshness,
    pub accepted_entry_count: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedLineupResult {
    pub save_status: String,
    pub accepted_lineup_status: AcceptedLineupStatus,
    pub accepted_entry_count: Option<u64>,
    pub reason_code: Option<SavedLineupReasonCode>,
}

#[derive(Clone, Debug, Deserialize)]
struct MachineWorkflowResult {
    #[serde(rename = "Status", default)]
    status: Option<String>,
    #[serde(rename = "CandidateManifestHash", default)]
    candidate_manifest_hash: Option<String>,
    #[serde(rename = "BuildIdentity", default)]
    build_identity: Option<String>,
    #[serde(rename = "ParentGenerationManifestHash", default)]
    parent_generation_manifest_hash: Option<String>,
    #[serde(rename = "AcceptedLineupStatus", default)]
    accepted_lineup_status: Option<String>,
    #[serde(rename = "AcceptedEntryCount", default)]
    accepted_entry_count: Option<u64>,
}

#[derive(Clone)]
struct SavedLineupPlanContext {
    workspace_path: PathBuf,
    playlist_path: PathBuf,
    guide_path: PathBuf,
    generation: u64,
    candidate_manifest_hash: String,
    build_identity: String,
    parent_generation_manifest_hash: Option<String>,
}

#[derive(Default)]
pub struct SetupSession {
    workspace_path: Option<PathBuf>,
    playlist_path: Option<PathBuf>,
    guide_path: Option<PathBuf>,
    generation: u64,
    saved_plan: Option<SavedLineupPlanContext>,
}

#[derive(Clone)]
struct SetupSessionSnapshot {
    workspace_path: Option<PathBuf>,
    playlist_path: Option<PathBuf>,
    guide_path: Option<PathBuf>,
    generation: u64,
}

#[derive(Clone, Debug, PartialEq)]
struct FileFingerprint {
    length: u64,
    modified: Option<std::time::SystemTime>,
}

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
#[serde(rename_all = "kebab-case")]
pub enum GuideContentStatus {
    NotChecked,
    Checking,
    Checked,
    NeedsAttention,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum GuideContentReasonCode {
    MissingRoot,
    EmptyGuide,
    IncompleteChannel,
    IncompleteProgramme,
    InvalidEncoding,
    TooLarge,
    UnsupportedFormat,
    MalformedXml,
    Unreadable,
    CheckUnavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GuideContentSummary {
    pub content_status: GuideContentStatus,
    pub channel_count: Option<u64>,
    pub programme_count: Option<u64>,
    pub reason_code: Option<GuideContentReasonCode>,
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
    #[serde(rename = "guideContent", skip_serializing_if = "Option::is_none")]
    pub guide_content: Option<GuideContentSummary>,
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

#[derive(Clone, Debug, PartialEq)]
struct PickerSelection {
    kind: PickerSelectionKind,
    path: PathBuf,
    pre_parse_check: PreParseCheck,
    playlist_content: Option<PlaylistContentSummary>,
    guide_content: Option<GuideContentSummary>,
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
                .map(|path| {
                    let pre_parse_check = check_directory(&path);
                    PickerSelection {
                        kind: PickerSelectionKind::Workspace,
                        path,
                        pre_parse_check,
                        playlist_content: None,
                        guide_content: None,
                    }
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
                        path,
                        pre_parse_check,
                        playlist_content: content,
                        guide_content: None,
                    }
                }),
            SetupSelectionKind::Guide => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose guide")
                .add_filter("Guide", &["xml", "xmltv", "gz", "zip"])
                .pick_file()
                .map(|path| {
                    let pre_parse_check = check_file(&path);
                    let content = if pre_parse_check == PreParseCheck::ReadyToInspect {
                        Some(inspect_guide_content(&path))
                    } else {
                        None
                    };
                    PickerSelection {
                        kind: PickerSelectionKind::File,
                        path,
                        pre_parse_check,
                        playlist_content: None,
                        guide_content: content,
                    }
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

fn inspect_playlist_reader<R: BufRead>(reader: R) -> Result<u64, PlaylistContentReasonCode> {
    inspect_playlist_reader_with_identities(reader, false).map(|(entry_count, _)| entry_count)
}

fn inspect_playlist_reader_with_identities<R: BufRead>(
    mut reader: R,
    capture_identities: bool,
) -> Result<(u64, Vec<Option<String>>), PlaylistContentReasonCode> {
    let mut line = Vec::new();
    let mut total_bytes = 0_u64;
    let mut first_physical_line = true;
    let mut saw_non_empty_line = false;
    let mut saw_header = false;
    let mut pending_tvg_id: Option<Option<String>> = None;
    let mut entry_count = 0_u64;
    let mut identities = Vec::new();

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
            if pending_tvg_id.is_some() {
                return Err(PlaylistContentReasonCode::IncompleteEntry);
            }
            pending_tvg_id = Some(if capture_identities {
                extract_m3u_tvg_id(trimmed)
            } else {
                None
            });
            continue;
        }

        if trimmed.starts_with('#') {
            continue;
        }

        let Some(tvg_id) = pending_tvg_id.take() else {
            return Err(PlaylistContentReasonCode::OrphanStreamLine);
        };
        entry_count = entry_count.saturating_add(1);
        if capture_identities {
            identities.push(tvg_id);
        }
    }

    if !saw_non_empty_line {
        return Err(PlaylistContentReasonCode::EmptyPlaylist);
    }
    if !saw_header {
        return Err(PlaylistContentReasonCode::MissingHeader);
    }
    if pending_tvg_id.is_some() {
        return Err(PlaylistContentReasonCode::IncompleteEntry);
    }
    if entry_count == 0 {
        return Err(PlaylistContentReasonCode::EmptyPlaylist);
    }

    Ok((entry_count, identities))
}

fn extract_m3u_tvg_id(text: &str) -> Option<String> {
    const MARKER: &str = "tvg-id=\"";

    for (index, _) in text.char_indices() {
        let marker_end = index.saturating_add(MARKER.len());
        let Some(marker) = text.get(index..marker_end) else {
            continue;
        };
        if !marker.eq_ignore_ascii_case(MARKER) {
            continue;
        }

        let value_start = marker_end;
        let value_end = text.get(value_start..)?.find('"')?;
        return Some(text[value_start..value_start + value_end].to_owned());
    }

    None
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
const MAX_GUIDE_BYTES: u64 = 64 * 1024 * 1024;
const MAX_GUIDE_COMPRESSED_BYTES: u64 = 64 * 1024 * 1024;
const GUIDE_OUTPUT_LIMIT_ERROR: &str = "guide output exceeds maximum size";

#[derive(Clone, Copy, PartialEq)]
enum GuideContentFormat {
    Plain,
    Gzip,
    Zip,
    Unsupported,
}

fn guide_content_format(path: &Path) -> GuideContentFormat {
    match path.extension().and_then(|extension| extension.to_str()) {
        Some(extension) if extension.eq_ignore_ascii_case("xml") => GuideContentFormat::Plain,
        Some(extension) if extension.eq_ignore_ascii_case("xmltv") => GuideContentFormat::Plain,
        Some(extension) if extension.eq_ignore_ascii_case("gz") => GuideContentFormat::Gzip,
        Some(extension) if extension.eq_ignore_ascii_case("zip") => GuideContentFormat::Zip,
        _ => GuideContentFormat::Unsupported,
    }
}

fn inspect_guide_content(path: &Path) -> GuideContentSummary {
    let format = guide_content_format(path);
    if format == GuideContentFormat::Unsupported {
        return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
    }

    let max_input_bytes = if format == GuideContentFormat::Plain {
        MAX_GUIDE_BYTES
    } else {
        MAX_GUIDE_COMPRESSED_BYTES
    };
    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) => return guide_content_failure(guide_io_reason(&error)),
    };
    if metadata.len() > max_input_bytes {
        return guide_content_failure(GuideContentReasonCode::TooLarge);
    }

    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(error) => return guide_content_failure(guide_io_reason(&error)),
    };

    match format {
        GuideContentFormat::Plain => {
            inspect_guide_reader_summary(BufReader::new(BoundedReader::new(file)))
        }
        GuideContentFormat::Gzip => {
            let decoder = MultiGzDecoder::new(file);
            inspect_guide_reader_summary(BufReader::new(BoundedReader::new(decoder)))
        }
        GuideContentFormat::Zip => inspect_zip_guide(file),
        GuideContentFormat::Unsupported => {
            guide_content_failure(GuideContentReasonCode::UnsupportedFormat)
        }
    }
}

fn inspect_guide_reader_summary<R: BufRead>(reader: R) -> GuideContentSummary {
    match inspect_guide_reader(reader) {
        Ok((channel_count, programme_count)) => GuideContentSummary {
            content_status: GuideContentStatus::Checked,
            channel_count: Some(channel_count),
            programme_count: Some(programme_count),
            reason_code: None,
        },
        Err(reason_code) => guide_content_failure(reason_code),
    }
}

fn inspect_zip_guide(file: fs::File) -> GuideContentSummary {
    let mut archive = match ZipArchive::new(file) {
        Ok(archive) => archive,
        Err(_) => return guide_content_failure(GuideContentReasonCode::UnsupportedFormat),
    };
    if archive.len() == 0 {
        return guide_content_failure(GuideContentReasonCode::EmptyGuide);
    }

    let mut guide_index = None;
    for index in 0..archive.len() {
        let entry = match archive.by_index(index) {
            Ok(entry) => entry,
            Err(_) => return guide_content_failure(GuideContentReasonCode::UnsupportedFormat),
        };
        if entry.is_dir() {
            continue;
        }
        if entry.encrypted() {
            return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
        }
        let extension = Path::new(entry.name())
            .extension()
            .and_then(|extension| extension.to_str());
        if extension.is_some_and(|extension| {
            extension.eq_ignore_ascii_case("gz")
                || extension.eq_ignore_ascii_case("gzip")
                || extension.eq_ignore_ascii_case("zip")
        }) {
            return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
        }
        if !extension.is_some_and(|extension| {
            extension.eq_ignore_ascii_case("xml") || extension.eq_ignore_ascii_case("xmltv")
        }) {
            return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
        }
        if guide_index.replace(index).is_some() {
            return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
        }
        if entry.size() > MAX_GUIDE_BYTES {
            return guide_content_failure(GuideContentReasonCode::TooLarge);
        }
    }

    let Some(guide_index) = guide_index else {
        return guide_content_failure(GuideContentReasonCode::EmptyGuide);
    };
    let entry = match archive.by_index(guide_index) {
        Ok(entry) => entry,
        Err(_) => return guide_content_failure(GuideContentReasonCode::UnsupportedFormat),
    };
    if entry.encrypted() {
        return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
    }
    inspect_guide_reader_summary(BufReader::new(BoundedReader::new(entry)))
}

fn guide_io_reason(error: &io::Error) -> GuideContentReasonCode {
    if error.kind() == io::ErrorKind::PermissionDenied {
        GuideContentReasonCode::Unreadable
    } else {
        GuideContentReasonCode::CheckUnavailable
    }
}

struct BoundedReader<R> {
    inner: R,
    bytes_read: u64,
}

impl<R: Read> BoundedReader<R> {
    fn new(inner: R) -> Self {
        Self {
            inner,
            bytes_read: 0,
        }
    }
}

impl<R: Read> Read for BoundedReader<R> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        if buffer.is_empty() {
            return Ok(0);
        }
        if self.bytes_read == MAX_GUIDE_BYTES {
            let mut probe = [0_u8; 1];
            return match self.inner.read(&mut probe) {
                Ok(0) => Ok(0),
                Ok(_) => Err(io::Error::new(
                    io::ErrorKind::Other,
                    GUIDE_OUTPUT_LIMIT_ERROR,
                )),
                Err(error) => Err(error),
            };
        }

        let remaining = MAX_GUIDE_BYTES - self.bytes_read;
        let allowed = usize::try_from(remaining)
            .unwrap_or(usize::MAX)
            .min(buffer.len());
        let bytes_read = self.inner.read(&mut buffer[..allowed])?;
        self.bytes_read = self.bytes_read.saturating_add(bytes_read as u64);
        Ok(bytes_read)
    }
}
fn inspect_guide_reader<R: BufRead>(reader: R) -> Result<(u64, u64), GuideContentReasonCode> {
    inspect_guide_reader_with_identities(reader, false)
        .map(|scan| (scan.channel_count, scan.programme_count))
}

struct GuideIdentityScan {
    channel_count: u64,
    programme_count: u64,
    channel_ids: Vec<String>,
}

fn inspect_guide_reader_with_identities<R: BufRead>(
    reader: R,
    capture_identities: bool,
) -> Result<GuideIdentityScan, GuideContentReasonCode> {
    let mut reader = Reader::from_reader(reader);
    reader.config_mut().check_end_names = true;
    let mut buffer = Vec::new();
    let mut depth = 0_usize;
    let mut saw_root = false;
    let mut root_closed = false;
    let mut channel_count = 0_u64;
    let mut programme_count = 0_u64;
    let mut channel_ids = Vec::new();

    loop {
        match reader.read_event_into(&mut buffer) {
            Ok(Event::Start(element)) => {
                if !saw_root {
                    if depth != 0 || element.local_name().as_ref() != "tv" {
                        return Err(GuideContentReasonCode::MissingRoot);
                    }
                    saw_root = true;
                    depth = 1;
                } else if root_closed || depth == 0 {
                    return Err(GuideContentReasonCode::MalformedXml);
                } else {
                    if let Some(channel_id) = inspect_guide_identity_element(
                        &element,
                        depth,
                        &mut channel_count,
                        &mut programme_count,
                        capture_identities,
                    )? {
                        channel_ids.push(channel_id);
                    }
                    depth += 1;
                }
            }
            Ok(Event::Empty(element)) => {
                if !saw_root {
                    if element.local_name().as_ref() != "tv" {
                        return Err(GuideContentReasonCode::MissingRoot);
                    }
                    saw_root = true;
                    root_closed = true;
                } else if root_closed || depth == 0 {
                    return Err(GuideContentReasonCode::MalformedXml);
                } else if let Some(channel_id) = inspect_guide_identity_element(
                    &element,
                    depth,
                    &mut channel_count,
                    &mut programme_count,
                    capture_identities,
                )? {
                    channel_ids.push(channel_id);
                }
            }
            Ok(Event::End(_)) => {
                if !saw_root || root_closed || depth == 0 {
                    return Err(GuideContentReasonCode::MalformedXml);
                }
                depth -= 1;
                if depth == 0 {
                    root_closed = true;
                }
            }
            Ok(Event::Text(text)) => {
                if depth == 0
                    && text
                        .as_ref()
                        .chars()
                        .any(|character| !character.is_ascii_whitespace())
                {
                    return Err(GuideContentReasonCode::MalformedXml);
                }
            }
            Ok(Event::CData(_)) if depth == 0 => {
                return Err(GuideContentReasonCode::MalformedXml);
            }
            Ok(Event::DocType(_)) | Ok(Event::GeneralRef(_)) => {
                return Err(GuideContentReasonCode::MalformedXml);
            }
            Ok(Event::Eof) => break,
            Ok(_) => {}
            Err(error) => return Err(guide_xml_error(error)),
        }
        buffer.clear();
    }

    if !saw_root {
        return Err(GuideContentReasonCode::MissingRoot);
    }
    if !root_closed || depth != 0 {
        return Err(GuideContentReasonCode::MalformedXml);
    }
    if channel_count == 0 || programme_count == 0 {
        return Err(GuideContentReasonCode::EmptyGuide);
    }

    Ok(GuideIdentityScan {
        channel_count,
        programme_count,
        channel_ids,
    })
}

fn inspect_guide_identity_element(
    element: &quick_xml::events::BytesStart<'_>,
    depth: usize,
    channel_count: &mut u64,
    programme_count: &mut u64,
    capture_identity: bool,
) -> Result<Option<String>, GuideContentReasonCode> {
    if depth != 1 {
        return Ok(None);
    }

    match element.local_name().as_ref() {
        "channel" => {
            if !guide_has_non_empty_attribute(element, "id")? {
                return Err(GuideContentReasonCode::IncompleteChannel);
            }
            let channel_id = if capture_identity {
                Some(
                    guide_attribute_value(element, "id")?
                        .ok_or(GuideContentReasonCode::IncompleteChannel)?,
                )
            } else {
                None
            };
            *channel_count = channel_count.saturating_add(1);
            Ok(channel_id)
        }
        "programme" => {
            if !guide_has_non_empty_attribute(element, "channel")?
                || !guide_has_non_empty_attribute(element, "start")?
                || !guide_has_non_empty_attribute(element, "stop")?
            {
                return Err(GuideContentReasonCode::IncompleteProgramme);
            }
            *programme_count = programme_count.saturating_add(1);
            Ok(None)
        }
        _ => Ok(None),
    }
}

fn guide_attribute_value(
    element: &quick_xml::events::BytesStart<'_>,
    name: &str,
) -> Result<Option<String>, GuideContentReasonCode> {
    for attribute in element.attributes().with_checks(true) {
        let attribute = attribute.map_err(|_| GuideContentReasonCode::MalformedXml)?;
        if attribute.key.as_ref() == name {
            return attribute
                .normalized_value(quick_xml::XmlVersion::default())
                .map(|value| Some(value.into_owned()))
                .map_err(|_| GuideContentReasonCode::MalformedXml);
        }
    }
    Ok(None)
}

fn guide_xml_error(error: quick_xml::Error) -> GuideContentReasonCode {
    match error {
        quick_xml::Error::Io(error) if error.to_string() == GUIDE_OUTPUT_LIMIT_ERROR => {
            GuideContentReasonCode::TooLarge
        }
        quick_xml::Error::Io(error)
            if matches!(
                error.kind(),
                io::ErrorKind::InvalidData | io::ErrorKind::UnexpectedEof
            ) =>
        {
            GuideContentReasonCode::MalformedXml
        }
        quick_xml::Error::Io(error) => guide_io_reason(&error),
        quick_xml::Error::Encoding(_) => GuideContentReasonCode::InvalidEncoding,
        _ => GuideContentReasonCode::MalformedXml,
    }
}

fn guide_has_non_empty_attribute(
    element: &quick_xml::events::BytesStart<'_>,
    name: &str,
) -> Result<bool, GuideContentReasonCode> {
    let mut found = false;
    for attribute in element.attributes().with_checks(true) {
        let attribute = attribute.map_err(|_| GuideContentReasonCode::MalformedXml)?;
        if attribute.key.as_ref() == name {
            found = attribute
                .value
                .as_ref()
                .chars()
                .any(|character| !character.is_ascii_whitespace());
        }
    }
    Ok(found)
}
fn inspect_playlist_identity_content(
    path: &Path,
) -> Result<(u64, Vec<Option<String>>), PlaylistContentReasonCode> {
    let metadata = fs::metadata(path).map_err(|error| {
        if error.kind() == io::ErrorKind::PermissionDenied {
            PlaylistContentReasonCode::Unreadable
        } else {
            PlaylistContentReasonCode::CheckUnavailable
        }
    })?;
    if metadata.len() > MAX_PLAYLIST_BYTES {
        return Err(PlaylistContentReasonCode::TooLarge);
    }
    let file = fs::File::open(path).map_err(content_io_reason)?;
    inspect_playlist_reader_with_identities(BufReader::new(file), true)
}

fn inspect_guide_identity_content(
    path: &Path,
) -> Result<GuideIdentityScan, GuideContentReasonCode> {
    let format = guide_content_format(path);
    if format == GuideContentFormat::Unsupported {
        return Err(GuideContentReasonCode::UnsupportedFormat);
    }
    let max_input_bytes = if format == GuideContentFormat::Plain {
        MAX_GUIDE_BYTES
    } else {
        MAX_GUIDE_COMPRESSED_BYTES
    };
    let metadata = fs::metadata(path).map_err(|error| guide_io_reason(&error))?;
    if metadata.len() > max_input_bytes {
        return Err(GuideContentReasonCode::TooLarge);
    }
    let file = fs::File::open(path).map_err(|error| guide_io_reason(&error))?;

    match format {
        GuideContentFormat::Plain => {
            inspect_guide_reader_with_identities(BufReader::new(BoundedReader::new(file)), true)
        }
        GuideContentFormat::Gzip => {
            let decoder = MultiGzDecoder::new(file);
            inspect_guide_reader_with_identities(BufReader::new(BoundedReader::new(decoder)), true)
        }
        GuideContentFormat::Zip => inspect_zip_guide_identities(file),
        GuideContentFormat::Unsupported => Err(GuideContentReasonCode::UnsupportedFormat),
    }
}

fn inspect_zip_guide_identities(
    file: fs::File,
) -> Result<GuideIdentityScan, GuideContentReasonCode> {
    let mut archive =
        ZipArchive::new(file).map_err(|_| GuideContentReasonCode::UnsupportedFormat)?;
    if archive.len() == 0 {
        return Err(GuideContentReasonCode::EmptyGuide);
    }

    let mut guide_index = None;
    for index in 0..archive.len() {
        let entry = archive
            .by_index(index)
            .map_err(|_| GuideContentReasonCode::UnsupportedFormat)?;
        if entry.is_dir() || entry.encrypted() {
            if entry.encrypted() {
                return Err(GuideContentReasonCode::UnsupportedFormat);
            }
            continue;
        }
        let extension = Path::new(entry.name())
            .extension()
            .and_then(|extension| extension.to_str());
        if extension.is_some_and(|extension| {
            extension.eq_ignore_ascii_case("gz")
                || extension.eq_ignore_ascii_case("gzip")
                || extension.eq_ignore_ascii_case("zip")
        }) || !extension.is_some_and(|extension| {
            extension.eq_ignore_ascii_case("xml") || extension.eq_ignore_ascii_case("xmltv")
        }) {
            return Err(GuideContentReasonCode::UnsupportedFormat);
        }
        if guide_index.replace(index).is_some() {
            return Err(GuideContentReasonCode::UnsupportedFormat);
        }
        if entry.size() > MAX_GUIDE_BYTES {
            return Err(GuideContentReasonCode::TooLarge);
        }
    }

    let Some(guide_index) = guide_index else {
        return Err(GuideContentReasonCode::EmptyGuide);
    };
    let entry = archive
        .by_index(guide_index)
        .map_err(|_| GuideContentReasonCode::UnsupportedFormat)?;
    if entry.encrypted() {
        return Err(GuideContentReasonCode::UnsupportedFormat);
    }
    inspect_guide_reader_with_identities(BufReader::new(BoundedReader::new(entry)), true)
}

fn file_fingerprint(path: &Path) -> io::Result<FileFingerprint> {
    let metadata = fs::metadata(path)?;
    Ok(FileFingerprint {
        length: metadata.len(),
        modified: metadata.modified().ok(),
    })
}

fn blocked_match(reason_code: MatchReasonCode) -> PlaylistGuideMatchSummary {
    PlaylistGuideMatchSummary {
        match_status: MatchStatus::Blocked,
        playlist_entry_count: None,
        guide_channel_count: None,
        matched_count: None,
        unmatched_playlist_count: None,
        ambiguous_count: None,
        guide_only_count: None,
        requires_review: false,
        reason_code: Some(reason_code),
    }
}

fn map_playlist_match_error(reason_code: PlaylistContentReasonCode) -> MatchReasonCode {
    match reason_code {
        PlaylistContentReasonCode::TooLarge => MatchReasonCode::TooLarge,
        PlaylistContentReasonCode::Unreadable => MatchReasonCode::PlaylistUnavailable,
        PlaylistContentReasonCode::CheckUnavailable => MatchReasonCode::CheckUnavailable,
        _ => MatchReasonCode::PlaylistContentInvalid,
    }
}

fn map_guide_match_error(reason_code: GuideContentReasonCode) -> MatchReasonCode {
    match reason_code {
        GuideContentReasonCode::TooLarge => MatchReasonCode::TooLarge,
        GuideContentReasonCode::UnsupportedFormat => MatchReasonCode::UnsupportedFormat,
        GuideContentReasonCode::Unreadable => MatchReasonCode::GuideUnavailable,
        GuideContentReasonCode::CheckUnavailable => MatchReasonCode::CheckUnavailable,
        _ => MatchReasonCode::GuideContentInvalid,
    }
}

fn evaluate_playlist_guide_match(
    playlist_path: &Path,
    guide_path: &Path,
) -> PlaylistGuideMatchSummary {
    if !playlist_path.extension().is_some_and(|extension| {
        extension.eq_ignore_ascii_case("m3u") || extension.eq_ignore_ascii_case("m3u8")
    }) {
        return blocked_match(MatchReasonCode::UnsupportedFormat);
    }

    let playlist_before = match file_fingerprint(playlist_path) {
        Ok(fingerprint) => fingerprint,
        Err(error) => {
            return blocked_match(if error.kind() == io::ErrorKind::PermissionDenied {
                MatchReasonCode::PlaylistUnavailable
            } else {
                MatchReasonCode::CheckUnavailable
            })
        }
    };
    let guide_before = match file_fingerprint(guide_path) {
        Ok(fingerprint) => fingerprint,
        Err(error) => {
            return blocked_match(if error.kind() == io::ErrorKind::PermissionDenied {
                MatchReasonCode::GuideUnavailable
            } else {
                MatchReasonCode::CheckUnavailable
            })
        }
    };
    let (playlist_entry_count, playlist_ids) =
        match inspect_playlist_identity_content(playlist_path) {
            Ok(scan) => scan,
            Err(reason_code) => return blocked_match(map_playlist_match_error(reason_code)),
        };
    let guide_scan = match inspect_guide_identity_content(guide_path) {
        Ok(scan) => scan,
        Err(reason_code) => return blocked_match(map_guide_match_error(reason_code)),
    };

    let playlist_after = match file_fingerprint(playlist_path) {
        Ok(fingerprint) => fingerprint,
        Err(_) => return blocked_match(MatchReasonCode::StaleSelection),
    };
    let guide_after = match file_fingerprint(guide_path) {
        Ok(fingerprint) => fingerprint,
        Err(_) => return blocked_match(MatchReasonCode::StaleSelection),
    };
    if playlist_before != playlist_after || guide_before != guide_after {
        return blocked_match(MatchReasonCode::StaleSelection);
    }

    let mut playlist_counts = std::collections::HashMap::<String, u64>::new();
    for identity in playlist_ids.iter().flatten() {
        if !identity.trim().is_empty() {
            *playlist_counts.entry(identity.clone()).or_default() += 1;
        }
    }
    let mut guide_counts = std::collections::HashMap::<String, u64>::new();
    for identity in &guide_scan.channel_ids {
        *guide_counts.entry(identity.clone()).or_default() += 1;
    }

    let mut matched_count = 0_u64;
    let mut unmatched_playlist_count = 0_u64;
    let mut ambiguous_count = 0_u64;
    for identity in &playlist_ids {
        let Some(identity) = identity else {
            unmatched_playlist_count = unmatched_playlist_count.saturating_add(1);
            continue;
        };
        if identity.trim().is_empty() {
            unmatched_playlist_count = unmatched_playlist_count.saturating_add(1);
            continue;
        }
        let playlist_count = playlist_counts.get(identity).copied().unwrap_or(0);
        let guide_count = guide_counts.get(identity).copied().unwrap_or(0);
        if playlist_count > 1 || guide_count > 1 {
            ambiguous_count = ambiguous_count.saturating_add(1);
        } else if guide_count == 0 {
            unmatched_playlist_count = unmatched_playlist_count.saturating_add(1);
        } else {
            matched_count = matched_count.saturating_add(1);
        }
    }

    let guide_only_count = guide_counts
        .iter()
        .filter(|(identity, _)| !playlist_counts.contains_key(*identity))
        .count() as u64;
    let (match_status, requires_review, reason_code) = if ambiguous_count > 0 {
        (
            MatchStatus::ReviewNeeded,
            true,
            Some(MatchReasonCode::AmbiguousIdentity),
        )
    } else if unmatched_playlist_count > 0 || guide_only_count > 0 {
        (
            MatchStatus::NeedsAttention,
            false,
            Some(MatchReasonCode::UnmatchedIdentity),
        )
    } else {
        (MatchStatus::Checked, false, None)
    };

    PlaylistGuideMatchSummary {
        match_status,
        playlist_entry_count: Some(playlist_entry_count),
        guide_channel_count: Some(guide_scan.channel_count),
        matched_count: Some(matched_count),
        unmatched_playlist_count: Some(unmatched_playlist_count),
        ambiguous_count: Some(ambiguous_count),
        guide_only_count: Some(guide_only_count),
        requires_review,
        reason_code,
    }
}

fn guide_content_failure(reason_code: GuideContentReasonCode) -> GuideContentSummary {
    GuideContentSummary {
        content_status: GuideContentStatus::NeedsAttention,
        channel_count: None,
        programme_count: None,
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
    guide_content: Option<GuideContentSummary>,
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
        guide_content: if kind == SetupSelectionKind::Guide {
            guide_content
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
        guide_content: None,
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
        guide_content: None,
    }
}

fn picker_result(
    kind: SetupSelectionKind,
    picked: Result<Option<PickerSelection>, PickerError>,
) -> SetupSelectionResult {
    match picked {
        Ok(Some(selection)) if selection.kind.matches(kind) => selected_result(
            kind,
            selection.pre_parse_check,
            selection.playlist_content,
            selection.guide_content,
        ),
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

#[cfg(test)]
fn choose_setup_item_with_adapter(
    kind: SetupSelectionKind,
    adapter: &dyn PickerAdapter,
) -> SetupSelectionResult {
    picker_result(kind, adapter.pick(kind))
}

fn remember_selection(session: &mut SetupSession, kind: SetupSelectionKind, path: PathBuf) {
    session.generation = session.generation.saturating_add(1);
    session.saved_plan = None;
    match kind {
        SetupSelectionKind::Workspace => {
            session.workspace_path = Some(path);
            session.playlist_path = None;
            session.guide_path = None;
        }
        SetupSelectionKind::Playlist => {
            session.playlist_path = Some(path);
            session.guide_path = None;
        }
        SetupSelectionKind::Guide => {
            session.guide_path = Some(path);
        }
    }
}

fn check_selected_playlist_guide(session: &Mutex<SetupSession>) -> PlaylistGuideMatchSummary {
    let snapshot = {
        let session = session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        SetupSessionSnapshot {
            workspace_path: session.workspace_path.clone(),
            playlist_path: session.playlist_path.clone(),
            guide_path: session.guide_path.clone(),
            generation: session.generation,
        }
    };
    let Some(playlist_path) = snapshot.playlist_path else {
        return blocked_match(MatchReasonCode::MissingPlaylist);
    };
    let Some(guide_path) = snapshot.guide_path else {
        return blocked_match(MatchReasonCode::MissingGuide);
    };

    let result = evaluate_playlist_guide_match(&playlist_path, &guide_path);
    let session = session
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if session.generation != snapshot.generation {
        return blocked_match(MatchReasonCode::StaleSelection);
    }
    result
}

const MACHINE_RESULT_PREFIX: &str = "CHANNELFORGE_MACHINE_RESULT:";

fn saved_lineup_plan_from_match(
    summary: &PlaylistGuideMatchSummary,
    plan_status: SavedLineupPlanStatus,
    accepted_lineup_status: AcceptedLineupStatus,
    candidate_freshness: CandidateFreshness,
    accepted_entry_count: Option<u64>,
) -> SavedLineupPlan {
    SavedLineupPlan {
        plan_status,
        playlist_entry_count: summary.playlist_entry_count,
        guide_channel_count: summary.guide_channel_count,
        matched_count: summary.matched_count,
        unmatched_playlist_count: summary.unmatched_playlist_count,
        ambiguous_count: summary.ambiguous_count,
        guide_only_count: summary.guide_only_count,
        requires_review: summary.requires_review,
        accepted_lineup_status,
        candidate_freshness,
        accepted_entry_count,
    }
}

fn unavailable_saved_lineup_plan() -> SavedLineupPlan {
    SavedLineupPlan {
        plan_status: SavedLineupPlanStatus::Blocked,
        playlist_entry_count: None,
        guide_channel_count: None,
        matched_count: None,
        unmatched_playlist_count: None,
        ambiguous_count: None,
        guide_only_count: None,
        requires_review: false,
        accepted_lineup_status: AcceptedLineupStatus::Unavailable,
        candidate_freshness: CandidateFreshness::Unknown,
        accepted_entry_count: None,
    }
}

fn saved_lineup_result(
    save_status: &str,
    accepted_lineup_status: AcceptedLineupStatus,
    accepted_entry_count: Option<u64>,
    reason_code: Option<SavedLineupReasonCode>,
) -> SavedLineupResult {
    SavedLineupResult {
        save_status: save_status.to_string(),
        accepted_lineup_status,
        accepted_entry_count,
        reason_code,
    }
}

fn session_snapshot(session: &Mutex<SetupSession>) -> SetupSessionSnapshot {
    let session = session
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    SetupSessionSnapshot {
        workspace_path: session.workspace_path.clone(),
        playlist_path: session.playlist_path.clone(),
        guide_path: session.guide_path.clone(),
        generation: session.generation,
    }
}

fn accepted_lineup_status(machine: &MachineWorkflowResult) -> AcceptedLineupStatus {
    match machine.accepted_lineup_status.as_deref() {
        Some(status) if status.eq_ignore_ascii_case("present") => AcceptedLineupStatus::Present,
        Some(status) if status.eq_ignore_ascii_case("none") => AcceptedLineupStatus::None,
        _ => AcceptedLineupStatus::Unavailable,
    }
}

fn machine_status(machine: &MachineWorkflowResult) -> &str {
    machine.status.as_deref().unwrap_or("")
}

fn valid_saved_workflow_paths(
    snapshot: &SetupSessionSnapshot,
) -> Option<(PathBuf, PathBuf, PathBuf)> {
    let workspace = fs::canonicalize(snapshot.workspace_path.as_ref()?).ok()?;
    let playlist = fs::canonicalize(snapshot.playlist_path.as_ref()?).ok()?;
    let guide = fs::canonicalize(snapshot.guide_path.as_ref()?).ok()?;
    if !workspace.is_dir()
        || !playlist.is_file()
        || !guide.is_file()
        || !playlist.starts_with(&workspace)
        || !guide.starts_with(&workspace)
    {
        return None;
    }
    Some((workspace, playlist, guide))
}
fn saved_workflow_script(workspace: &Path) -> Option<PathBuf> {
    let workspace_script = workspace.join("scripts").join("Build-My-Lineup.ps1");
    if workspace_script.is_file() {
        return Some(workspace_script);
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../scripts/Build-My-Lineup.ps1")
        .canonicalize()
        .ok()
        .filter(|path| path.is_file())
}

fn run_saved_workflow(
    workspace: &Path,
    playlist: &Path,
    guide: &Path,
    accept: Option<(&str, &str, &str)>,
) -> Result<MachineWorkflowResult, SavedLineupReasonCode> {
    let Some(script) = saved_workflow_script(workspace) else {
        return Err(SavedLineupReasonCode::NativeUnavailable);
    };
    let mut command = Command::new("pwsh");
    command
        .arg("-NoProfile")
        .arg("-NonInteractive")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(script)
        .arg("-Root")
        .arg(workspace)
        .arg("-M3UPath")
        .arg(playlist)
        .arg("-XMLTVPath")
        .arg(guide)
        .arg("-MachineResult");
    match accept {
        Some((candidate_hash, build_identity, parent_hash)) => {
            command
                .arg("-Accept")
                .arg("-AmbiguousAction")
                .arg("Cancel")
                .arg("-ExpectedCandidateManifestHash")
                .arg(candidate_hash)
                .arg("-ExpectedParentGenerationManifestHash")
                .arg(parent_hash)
                .arg("-ExpectedBuildIdentity")
                .arg(build_identity);
        }
        None => {
            command.arg("-PlanOnly");
        }
    }
    let output = command
        .output()
        .map_err(|_| SavedLineupReasonCode::NativeUnavailable)?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let marker = stdout
        .lines()
        .rev()
        .find_map(|line| line.strip_prefix(MACHINE_RESULT_PREFIX))
        .ok_or(SavedLineupReasonCode::AcceptanceFailed)?;
    let machine = serde_json::from_str::<MachineWorkflowResult>(marker)
        .map_err(|_| SavedLineupReasonCode::AcceptanceFailed)?;
    if !output.status.success() && !machine_status(&machine).eq_ignore_ascii_case("STALE") {
        return Err(SavedLineupReasonCode::AcceptanceFailed);
    }
    Ok(machine)
}

fn prepare_saved_lineup_plan_inner(session: &Mutex<SetupSession>) -> SavedLineupPlan {
    let summary = check_selected_playlist_guide(session);
    if summary.match_status != MatchStatus::Checked {
        let plan_status = match summary.match_status {
            MatchStatus::NotChecked | MatchStatus::Checking => SavedLineupPlanStatus::NotReady,
            _ => SavedLineupPlanStatus::Blocked,
        };
        let plan = saved_lineup_plan_from_match(
            &summary,
            plan_status,
            AcceptedLineupStatus::Unavailable,
            CandidateFreshness::Unknown,
            None,
        );
        session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .saved_plan = None;
        return plan;
    }

    let snapshot = session_snapshot(session);
    let Some((workspace, playlist, guide)) = valid_saved_workflow_paths(&snapshot) else {
        return unavailable_saved_lineup_plan();
    };
    let machine = match run_saved_workflow(&workspace, &playlist, &guide, None) {
        Ok(machine) => machine,
        Err(_) => return unavailable_saved_lineup_plan(),
    };
    let status = machine_status(&machine);
    let accepted_status = accepted_lineup_status(&machine);
    let candidate_ready = status.eq_ignore_ascii_case("PROPOSAL_READY")
        && machine
            .candidate_manifest_hash
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        && machine
            .build_identity
            .as_deref()
            .is_some_and(|value| !value.is_empty());
    let freshness = if candidate_ready {
        CandidateFreshness::Current
    } else if status.eq_ignore_ascii_case("STALE") {
        CandidateFreshness::Stale
    } else {
        CandidateFreshness::Unknown
    };
    let plan = saved_lineup_plan_from_match(
        &summary,
        if candidate_ready {
            SavedLineupPlanStatus::Ready
        } else if freshness == CandidateFreshness::Stale {
            SavedLineupPlanStatus::Stale
        } else {
            SavedLineupPlanStatus::Blocked
        },
        accepted_status,
        freshness,
        machine.accepted_entry_count,
    );
    if !candidate_ready {
        return plan;
    }
    let Some(candidate_manifest_hash) = machine.candidate_manifest_hash else {
        return unavailable_saved_lineup_plan();
    };
    let Some(build_identity) = machine.build_identity else {
        return unavailable_saved_lineup_plan();
    };
    let context = SavedLineupPlanContext {
        workspace_path: workspace,
        playlist_path: playlist,
        guide_path: guide,
        generation: snapshot.generation,
        candidate_manifest_hash,
        build_identity,
        parent_generation_manifest_hash: machine.parent_generation_manifest_hash,
    };
    let mut session = session
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if session.generation != snapshot.generation {
        session.saved_plan = None;
        return SavedLineupPlan {
            plan_status: SavedLineupPlanStatus::Stale,
            candidate_freshness: CandidateFreshness::Stale,
            ..plan
        };
    }
    session.saved_plan = Some(context);
    plan
}

fn accept_saved_lineup_inner(session: &Mutex<SetupSession>) -> SavedLineupResult {
    let context = {
        let session = session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        session.saved_plan.clone()
    };
    let Some(context) = context else {
        return saved_lineup_result(
            "blocked",
            AcceptedLineupStatus::Unavailable,
            None,
            Some(SavedLineupReasonCode::NotEligible),
        );
    };
    let snapshot = session_snapshot(session);
    let Some((workspace, playlist, guide)) = valid_saved_workflow_paths(&snapshot) else {
        session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .saved_plan = None;
        return saved_lineup_result(
            "stale",
            AcceptedLineupStatus::Unavailable,
            None,
            Some(SavedLineupReasonCode::StaleCandidate),
        );
    };
    if snapshot.generation != context.generation
        || workspace != context.workspace_path
        || playlist != context.playlist_path
        || guide != context.guide_path
    {
        session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .saved_plan = None;
        return saved_lineup_result(
            "stale",
            AcceptedLineupStatus::Unavailable,
            None,
            Some(SavedLineupReasonCode::StaleCandidate),
        );
    }
    let summary = check_selected_playlist_guide(session);
    if summary.match_status != MatchStatus::Checked {
        session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .saved_plan = None;
        return saved_lineup_result(
            "blocked",
            AcceptedLineupStatus::Unavailable,
            None,
            Some(SavedLineupReasonCode::NotEligible),
        );
    }
    let parent_hash = context
        .parent_generation_manifest_hash
        .as_deref()
        .unwrap_or("");
    let machine = match run_saved_workflow(
        &context.workspace_path,
        &context.playlist_path,
        &context.guide_path,
        Some((
            &context.candidate_manifest_hash,
            &context.build_identity,
            parent_hash,
        )),
    ) {
        Ok(machine) => machine,
        Err(reason) => {
            return saved_lineup_result(
                "blocked",
                AcceptedLineupStatus::Unavailable,
                None,
                Some(reason),
            );
        }
    };
    let status = machine_status(&machine);
    if status.eq_ignore_ascii_case("STALE") {
        session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .saved_plan = None;
        return saved_lineup_result(
            "stale",
            AcceptedLineupStatus::Unavailable,
            None,
            Some(SavedLineupReasonCode::StaleCandidate),
        );
    }
    if status.eq_ignore_ascii_case("PUBLISHED") || status.eq_ignore_ascii_case("ALREADY_ACCEPTED") {
        session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .saved_plan = None;
        return saved_lineup_result(
            "saved",
            AcceptedLineupStatus::Present,
            machine.accepted_entry_count,
            None,
        );
    }
    saved_lineup_result(
        "blocked",
        accepted_lineup_status(&machine),
        machine.accepted_entry_count,
        Some(SavedLineupReasonCode::AcceptanceFailed),
    )
}

fn choose_setup_item_with_session(
    kind: SetupSelectionKind,
    adapter: &dyn PickerAdapter,
    session: &Mutex<SetupSession>,
) -> SetupSelectionResult {
    let picked = adapter.pick(kind);
    if let Ok(Some(selection)) = &picked {
        if selection.kind.matches(kind) {
            let mut session = session
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            remember_selection(&mut session, kind, selection.path.clone());
        }
    }
    picker_result(kind, picked)
}

mod command {
    use super::*;

    #[tauri::command]
    pub async fn choose_setup_item(
        kind: SetupSelectionKind,
        window: Window,
        session: State<'_, Mutex<SetupSession>>,
    ) -> Result<SetupSelectionResult, String> {
        Ok(choose_setup_item_with_session(
            kind,
            &NativePicker { window: &window },
            session.inner(),
        ))
    }

    #[tauri::command]
    pub async fn check_playlist_guide_match(
        session: State<'_, Mutex<SetupSession>>,
    ) -> Result<PlaylistGuideMatchSummary, String> {
        Ok(check_selected_playlist_guide(session.inner()))
    }

    #[tauri::command]
    pub async fn prepare_saved_lineup_plan(
        session: State<'_, Mutex<SetupSession>>,
    ) -> Result<SavedLineupPlan, String> {
        Ok(prepare_saved_lineup_plan_inner(session.inner()))
    }

    #[tauri::command]
    pub async fn accept_saved_lineup(
        session: State<'_, Mutex<SetupSession>>,
    ) -> Result<SavedLineupResult, String> {
        Ok(accept_saved_lineup_inner(session.inner()))
    }
}

pub use command::{
    accept_saved_lineup, check_playlist_guide_match, choose_setup_item, prepare_saved_lineup_plan,
};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(Mutex::new(SetupSession::default()))
        .invoke_handler(tauri::generate_handler![
            command::choose_setup_item,
            command::check_playlist_guide_match,
            command::prepare_saved_lineup_plan,
            command::accept_saved_lineup
        ])
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
            self.result.clone()
        }
    }

    fn ready_selection(kind: PickerSelectionKind) -> PickerSelection {
        PickerSelection {
            kind,
            path: PathBuf::from("fixture"),
            pre_parse_check: PreParseCheck::ReadyToInspect,
            playlist_content: None,
            guide_content: None,
        }
    }

    fn scan(content: &str) -> Result<u64, PlaylistContentReasonCode> {
        inspect_playlist_reader(std::io::Cursor::new(content.as_bytes()))
    }

    fn scan_guide(content: &str) -> Result<(u64, u64), GuideContentReasonCode> {
        inspect_guide_reader(std::io::Cursor::new(content.as_bytes()))
    }

    fn guide_test_path(extension: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "channelforge-guide-{}-{}.{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("system clock should be after epoch")
                .as_nanos(),
            extension
        ))
    }

    fn write_guide_file(extension: &str, bytes: &[u8]) -> std::path::PathBuf {
        let path = guide_test_path(extension);
        fs::write(&path, bytes).expect("guide fixture should be written");
        path
    }

    fn valid_guide_xml() -> &'static [u8] {
        br#"<tv><channel id="channel" /><programme channel="channel" start="start" stop="stop" /></tv>"#
    }

    fn gzip_guide(content: &[u8]) -> Vec<u8> {
        use std::io::Write;

        let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        encoder
            .write_all(content)
            .expect("gzip fixture should be written");
        encoder.finish().expect("gzip fixture should finish")
    }

    fn zip_guide(entries: &[(&str, &[u8])]) -> Vec<u8> {
        use std::io::Write;

        let cursor = std::io::Cursor::new(Vec::new());
        let mut writer = zip::ZipWriter::new(cursor);
        for (name, content) in entries {
            writer
                .start_file(*name, zip::write::SimpleFileOptions::default())
                .expect("zip entry should start");
            writer
                .write_all(content)
                .expect("zip entry should be written");
        }
        writer
            .finish()
            .expect("zip fixture should finish")
            .into_inner()
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
    fn scans_direct_xmltv_channels_and_programmes_without_retaining_content() {
        let counts = scan_guide(
            "\u{feff}<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
             <tv generator-info-name=\"hidden-generator\">\n\
               <!-- hidden comment -->\n\
               <channel id=\"hidden-channel\"><display-name>Hidden Channel</display-name><icon src=\"https://example.invalid/hidden.png\" /></channel>\n\
               <metadata><channel id=\"nested-channel\" /></metadata>\n\
               <programme channel=\"hidden-channel\" start=\"hidden-start\" stop=\"hidden-stop\"><title>Hidden Programme</title><desc>Hidden description</desc></programme>\n\
               <programme channel=\"hidden-channel\" start=\"another-start\" stop=\"another-stop\" />\n\
             </tv>",
        )
        .expect("valid XMLTV should scan");

        assert_eq!(counts, (1, 2));
    }

    #[test]
    fn maps_xmltv_structural_failures_to_safe_reasons() {
        let cases = [
            ("<guide />", GuideContentReasonCode::MissingRoot),
            ("<tv />", GuideContentReasonCode::EmptyGuide),
            (
                "<tv><channel /></tv>",
                GuideContentReasonCode::IncompleteChannel,
            ),
            (
                "<tv><channel id=\"channel\" /><programme start=\"start\" stop=\"stop\" /></tv>",
                GuideContentReasonCode::IncompleteProgramme,
            ),
            (
                "<tv><channel id=\"channel\"><display-name>Channel</display-name></tv>",
                GuideContentReasonCode::MalformedXml,
            ),
            (
                "<!DOCTYPE tv SYSTEM \"https://example.invalid/guide.dtd\"><tv />",
                GuideContentReasonCode::MalformedXml,
            ),
        ];

        for (content, reason_code) in cases {
            assert_eq!(scan_guide(content), Err(reason_code));
        }
    }

    #[test]
    fn scans_gzip_and_single_guide_zip_payloads() {
        let gzip_path = write_guide_file("gz", &gzip_guide(valid_guide_xml()));
        let gzip_summary = inspect_guide_content(&gzip_path);
        assert_eq!(gzip_summary.content_status, GuideContentStatus::Checked);
        assert_eq!(gzip_summary.channel_count, Some(1));
        assert_eq!(gzip_summary.programme_count, Some(1));
        fs::remove_file(&gzip_path).expect("gzip fixture should be removed");

        let zip_path = write_guide_file("zip", &zip_guide(&[("guide.xml", valid_guide_xml())]));
        let zip_summary = inspect_guide_content(&zip_path);
        assert_eq!(zip_summary.content_status, GuideContentStatus::Checked);
        assert_eq!(zip_summary.channel_count, Some(1));
        assert_eq!(zip_summary.programme_count, Some(1));
        fs::remove_file(&zip_path).expect("zip fixture should be removed");
    }

    #[test]
    fn rejects_invalid_encoding_and_unsafe_compressed_guides() {
        let invalid_path = write_guide_file("xml", b"<tv>\xff</tv>");
        let invalid = inspect_guide_content(&invalid_path);
        assert_eq!(
            invalid.reason_code,
            Some(GuideContentReasonCode::InvalidEncoding)
        );
        fs::remove_file(&invalid_path).expect("invalid fixture should be removed");

        let malformed_gzip_path = write_guide_file("gz", b"not-gzip");
        let malformed_gzip = inspect_guide_content(&malformed_gzip_path);
        assert_eq!(
            malformed_gzip.reason_code,
            Some(GuideContentReasonCode::MalformedXml)
        );
        fs::remove_file(&malformed_gzip_path).expect("malformed gzip fixture should be removed");

        let empty_zip_path = write_guide_file("zip", &zip_guide(&[]));
        let empty_zip = inspect_guide_content(&empty_zip_path);
        assert_eq!(
            empty_zip.reason_code,
            Some(GuideContentReasonCode::EmptyGuide)
        );
        fs::remove_file(&empty_zip_path).expect("empty zip fixture should be removed");

        let multi_guide_path = write_guide_file(
            "zip",
            &zip_guide(&[
                ("first.xml", valid_guide_xml()),
                ("second.xmltv", valid_guide_xml()),
            ]),
        );
        let multi_guide = inspect_guide_content(&multi_guide_path);
        assert_eq!(
            multi_guide.reason_code,
            Some(GuideContentReasonCode::UnsupportedFormat)
        );
        fs::remove_file(&multi_guide_path).expect("multi-guide fixture should be removed");

        let nested_path = write_guide_file("zip", &zip_guide(&[("guide.xml.gz", b"nested")]));
        let nested = inspect_guide_content(&nested_path);
        assert_eq!(
            nested.reason_code,
            Some(GuideContentReasonCode::UnsupportedFormat)
        );
        fs::remove_file(&nested_path).expect("nested fixture should be removed");

        let ambiguous_path = write_guide_file(
            "zip",
            &zip_guide(&[
                ("guide.xml", valid_guide_xml()),
                ("README.txt", b"ambiguous"),
            ]),
        );
        let ambiguous = inspect_guide_content(&ambiguous_path);
        assert_eq!(
            ambiguous.reason_code,
            Some(GuideContentReasonCode::UnsupportedFormat)
        );
        fs::remove_file(&ambiguous_path).expect("ambiguous fixture should be removed");

        let oversized_path = guide_test_path("gz");
        let oversized_file = fs::File::create(&oversized_path).expect("fixture should be created");
        oversized_file
            .set_len(MAX_GUIDE_COMPRESSED_BYTES + 1)
            .expect("fixture should be oversized");
        let oversized = inspect_guide_content(&oversized_path);
        assert_eq!(
            oversized.reason_code,
            Some(GuideContentReasonCode::TooLarge)
        );
        fs::remove_file(&oversized_path).expect("oversized fixture should be removed");

        let mut oversized_xml = valid_guide_xml().to_vec();
        oversized_xml.resize(MAX_GUIDE_BYTES as usize + 1, b' ');
        let oversized_output_path = write_guide_file("gz", &gzip_guide(&oversized_xml));
        let oversized_output = inspect_guide_content(&oversized_output_path);
        assert_eq!(
            oversized_output.reason_code,
            Some(GuideContentReasonCode::TooLarge)
        );
        fs::remove_file(&oversized_output_path)
            .expect("oversized output fixture should be removed");
    }

    #[test]
    fn bounded_reader_rejects_output_beyond_final_guide_limit() {
        let mut reader = BoundedReader::new(std::io::repeat(0));
        let mut chunk = vec![0_u8; 1024 * 1024];
        let error = loop {
            match reader.read(&mut chunk) {
                Ok(_) => {}
                Err(error) => break error,
            }
        };

        assert_eq!(error.kind(), io::ErrorKind::Other);
        assert_eq!(error.to_string(), GUIDE_OUTPUT_LIMIT_ERROR);
    }

    #[test]
    fn serializes_guide_summary_without_native_or_raw_values() {
        let summary = GuideContentSummary {
            content_status: GuideContentStatus::Checked,
            channel_count: Some(2),
            programme_count: Some(4),
            reason_code: None,
        };
        let serialized = serde_json::to_value(summary).expect("summary should serialize");
        let serialized_text = serialized.to_string();

        assert_eq!(serialized["contentStatus"], "checked");
        assert_eq!(serialized["channelCount"], 2);
        assert_eq!(serialized["programmeCount"], 4);
        assert!(serialized["reasonCode"].is_null());
        for forbidden in [
            "hidden-channel",
            "Hidden Programme",
            "https://example.invalid",
            "path",
            "filename",
            "url",
            "credentials",
            "token",
        ] {
            assert!(!serialized_text.contains(forbidden));
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
                selected_result(kind, PreParseCheck::ReadyToInspect, None, None)
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
                        path: PathBuf::from("fixture"),
                        pre_parse_check: PreParseCheck::NeedsAttention(reason),
                        playlist_content: None,
                        guide_content: None,
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
            None,
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
    fn serializes_guide_content_only_as_safe_aggregate_fields() {
        let serialized = serde_json::to_value(selected_result(
            SetupSelectionKind::Guide,
            PreParseCheck::ReadyToInspect,
            None,
            Some(GuideContentSummary {
                content_status: GuideContentStatus::Checked,
                channel_count: Some(2),
                programme_count: Some(4),
                reason_code: None,
            }),
        ))
        .expect("selection result should serialize");
        let serialized_text = serialized.to_string();

        assert_eq!(serialized["kind"], "guide");
        assert_eq!(serialized["guideContent"]["contentStatus"], "checked");
        assert_eq!(serialized["guideContent"]["channelCount"], 2);
        assert_eq!(serialized["guideContent"]["programmeCount"], 4);
        assert!(serialized.get("playlistContent").is_none());
        for forbidden in [
            "path",
            "filename",
            "url",
            "title",
            "channel-id",
            "credentials",
            "token",
        ] {
            assert!(!serialized_text.contains(forbidden));
        }
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
    fn playlist_test_path() -> PathBuf {
        std::env::temp_dir().join(format!(
            "channelforge-playlist-{}-{}.m3u",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("system clock should be after epoch")
                .as_nanos(),
        ))
    }

    fn write_playlist_file(content: &str) -> PathBuf {
        let path = playlist_test_path();
        fs::write(&path, content).expect("playlist fixture should be written");
        path
    }

    fn match_guide_xml(channels: &[&str]) -> String {
        let channel_xml = channels
            .iter()
            .map(|channel| format!(r#"<channel id="{channel}" />"#))
            .collect::<String>();
        let programme_xml = channels
            .first()
            .map(|channel| {
                format!(r#"<programme channel="{channel}" start="start" stop="stop" />"#)
            })
            .unwrap_or_default();
        format!("<tv>{channel_xml}{programme_xml}</tv>")
    }

    #[test]
    fn classifies_exact_unmatched_and_guide_only_relationships() {
        let playlist = write_playlist_file(
            "#EXTM3U\n\
             #EXTINF:-1 tvg-id=\"matched\",Hidden Name\n\
             https://secret.invalid/matched\n\
             #EXTINF:-1,No Identity\n\
             https://secret.invalid/missing\n\
             #EXTINF:-1 tvg-id=\"unknown\",Unknown Name\n\
             https://secret.invalid/unknown\n",
        );
        let guide = write_guide_file(
            "xml",
            match_guide_xml(&["matched", "guide-only"]).as_bytes(),
        );

        let summary = evaluate_playlist_guide_match(&playlist, &guide);

        assert_eq!(summary.match_status, MatchStatus::NeedsAttention);
        assert_eq!(summary.playlist_entry_count, Some(3));
        assert_eq!(summary.guide_channel_count, Some(2));
        assert_eq!(summary.matched_count, Some(1));
        assert_eq!(summary.unmatched_playlist_count, Some(2));
        assert_eq!(summary.ambiguous_count, Some(0));
        assert_eq!(summary.guide_only_count, Some(1));
        assert!(!summary.requires_review);
        fs::remove_file(playlist).expect("playlist fixture should be removed");
        fs::remove_file(guide).expect("guide fixture should be removed");
    }

    #[test]
    fn ambiguity_takes_precedence_for_duplicate_playlist_and_guide_identities() {
        let playlist = write_playlist_file(
            "#EXTM3U\n\
             #EXTINF:-1 tvg-id=\"same\",First\n\
             opaque-one\n\
             #EXTINF:-1 tvg-id=\"same\",Second\n\
             opaque-two\n",
        );
        let guide = write_guide_file(
            "xml",
            br#"<tv>
                <channel id="same" />
                <channel id="same" />
                <programme channel="same" start="start" stop="stop" />
            </tv>"#,
        );

        let summary = evaluate_playlist_guide_match(&playlist, &guide);

        assert_eq!(summary.match_status, MatchStatus::ReviewNeeded);
        assert_eq!(summary.matched_count, Some(0));
        assert_eq!(summary.unmatched_playlist_count, Some(0));
        assert_eq!(summary.ambiguous_count, Some(2));
        assert_eq!(summary.guide_only_count, Some(0));
        assert!(summary.requires_review);
        assert_eq!(
            summary.reason_code,
            Some(MatchReasonCode::AmbiguousIdentity)
        );
        fs::remove_file(playlist).expect("playlist fixture should be removed");
        fs::remove_file(guide).expect("guide fixture should be removed");
    }

    #[test]
    fn match_summary_is_deterministic_and_contains_only_safe_fields() {
        let playlist = write_playlist_file(
            "#EXTM3U\n#EXTINF:-1 tvg-id=\"same\",Hidden Name\nhttps://secret.invalid/stream\n",
        );
        let guide = write_guide_file("xml", match_guide_xml(&["same"]).as_bytes());

        let first = evaluate_playlist_guide_match(&playlist, &guide);
        let second = evaluate_playlist_guide_match(&playlist, &guide);
        assert_eq!(first, second);

        let serialized = serde_json::to_string(&first).expect("summary should serialize");
        for forbidden in [
            "same",
            "Hidden Name",
            "https://secret.invalid",
            "stream",
            "path",
            "filename",
            "token",
            "password",
            "credential",
        ] {
            assert!(!serialized.contains(forbidden));
        }
        fs::remove_file(playlist).expect("playlist fixture should be removed");
        fs::remove_file(guide).expect("guide fixture should be removed");
    }

    #[test]
    fn blocks_missing_or_invalid_inputs_and_invalidates_reselected_paths() {
        let missing = check_selected_playlist_guide(&Mutex::new(SetupSession::default()));
        assert_eq!(missing.match_status, MatchStatus::Blocked);
        assert_eq!(missing.reason_code, Some(MatchReasonCode::MissingPlaylist));

        let malformed_playlist = write_playlist_file("#EXTINF:-1,not-a-playlist\nopaque\n");
        let valid_guide = write_guide_file("xml", match_guide_xml(&["same"]).as_bytes());
        let malformed = evaluate_playlist_guide_match(&malformed_playlist, &valid_guide);
        assert_eq!(malformed.match_status, MatchStatus::Blocked);
        assert_eq!(
            malformed.reason_code,
            Some(MatchReasonCode::PlaylistContentInvalid)
        );
        fs::remove_file(malformed_playlist).expect("playlist fixture should be removed");
        fs::remove_file(valid_guide).expect("guide fixture should be removed");

        let playlist = write_playlist_file("#EXTM3U\n#EXTINF:-1 tvg-id=\"same\",Name\nopaque\n");
        let unsupported_guide = write_guide_file("txt", match_guide_xml(&["same"]).as_bytes());
        let unsupported = evaluate_playlist_guide_match(&playlist, &unsupported_guide);
        assert_eq!(unsupported.match_status, MatchStatus::Blocked);
        assert_eq!(
            unsupported.reason_code,
            Some(MatchReasonCode::UnsupportedFormat)
        );
        fs::remove_file(playlist).expect("playlist fixture should be removed");
        fs::remove_file(unsupported_guide).expect("guide fixture should be removed");

        let session = Mutex::new(SetupSession::default());
        let mut session_guard = session.lock().expect("session should lock");
        remember_selection(
            &mut session_guard,
            SetupSelectionKind::Playlist,
            PathBuf::from("one.m3u"),
        );
        drop(session_guard);
        let first_generation = session.lock().expect("session should lock").generation;
        let mut session_guard = session.lock().expect("session should lock");
        remember_selection(
            &mut session_guard,
            SetupSelectionKind::Guide,
            PathBuf::from("one.xml"),
        );
        drop(session_guard);
        let second_generation = session.lock().expect("session should lock").generation;
        assert!(second_generation > first_generation);
        let mut session_guard = session.lock().expect("session should lock");
        remember_selection(
            &mut session_guard,
            SetupSelectionKind::Playlist,
            PathBuf::from("two.m3u"),
        );
        drop(session_guard);
        let session = session.lock().expect("session should lock");
        assert_eq!(session.guide_path, None);
        assert_eq!(session.playlist_path, Some(PathBuf::from("two.m3u")));
    }
    #[test]
    fn saved_lineup_plan_is_checked_only_and_redacts_source_values() {
        let summary = PlaylistGuideMatchSummary {
            match_status: MatchStatus::Checked,
            playlist_entry_count: Some(2),
            guide_channel_count: Some(2),
            matched_count: Some(2),
            unmatched_playlist_count: Some(0),
            ambiguous_count: Some(0),
            guide_only_count: Some(0),
            requires_review: false,
            reason_code: None,
        };
        let plan = saved_lineup_plan_from_match(
            &summary,
            SavedLineupPlanStatus::Ready,
            AcceptedLineupStatus::None,
            CandidateFreshness::Current,
            None,
        );
        assert_eq!(plan.plan_status, SavedLineupPlanStatus::Ready);
        let serialized = serde_json::to_string(&plan).expect("plan should serialize");
        for forbidden in [
            "candidate_manifest_hash",
            "generation",
            "https://",
            "stream",
            "path",
            "token",
            "password",
        ] {
            assert!(!serialized.contains(forbidden));
        }
    }

    #[test]
    fn acceptance_without_a_native_plan_is_blocked() {
        let result = accept_saved_lineup_inner(&Mutex::new(SetupSession::default()));
        assert_eq!(result.save_status, "blocked");
        assert_eq!(result.reason_code, Some(SavedLineupReasonCode::NotEligible));
        assert_eq!(
            result.accepted_lineup_status,
            AcceptedLineupStatus::Unavailable
        );
    }
}
