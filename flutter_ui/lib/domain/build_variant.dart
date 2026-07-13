/// Compile-time application variant selected by the Tizen packaging scripts.
///
/// The forced variant never trusts persisted UI state for game mode: every
/// stream request is serialized with game mode enabled and the setting itself
/// is omitted from the UI.
const bool kForceGameMode = bool.fromEnvironment('MOONLIGHT_FORCE_GAME_MODE');
