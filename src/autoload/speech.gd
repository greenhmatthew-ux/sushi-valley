extends Node
## Japanese pronunciation for recall prompts, via the OS's built-in text-to-speech
## (DisplayServer.tts_speak). Godot port of the TS build's src/game/systems/Speech.ts,
## which used the browser's Web Speech API. Synthesized directly from the card's own
## Japanese text (never a bundled clip — the imported decks carry no audio files), so
## there is no manifest to keep in sync and no way for a clip to mismatch its card.
##
## Port note — the bug this fixes: the TS build silently fell back to the system's
## default voice when no Japanese one was installed, while still asking for lang=ja-JP.
## An English voice reading kana/kanji doesn't mispronounce it so much as spell it out
## letter by letter, and browsers vary wildly in their fallback rate. This port never
## does that: speak() only ever uses a confirmed Japanese voice (picked by the pure,
## headless-tested SpeechLogic — see src/systems/speech_logic.gd), and is a silent no-op
## if the OS has none — it never guesses with the wrong voice.

const RATE := 0.8     # a touch slower than 1.0 helps beginners parse mora boundaries
const PITCH := 1.0
const VOLUME := 80

var _voice_id: String = ""   # "" once probed and no Japanese voice was found
var _probed: bool = false


func _ready() -> void:
	_probe_voice()


func is_available() -> bool:
	if not _probed:
		_probe_voice()
	return _voice_id != ""


## Speak Japanese text (kana/kanji/romaji), e.g. a card's prompt or reading. No-op if no
## Japanese voice is installed, TTS isn't supported on this platform, or text is empty.
## Interrupts any utterance already in flight so rapid card advances don't queue up and
## fall behind what's on screen.
func speak(text: String) -> void:
	if text.is_empty() or not is_available():
		return
	if DisplayServer.tts_is_speaking():
		DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, _voice_id, VOLUME, PITCH, RATE, 0, true)


func _probe_voice() -> void:
	_probed = true
	_voice_id = ""
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	_voice_id = SpeechLogic.pick_best_voice(DisplayServer.tts_get_voices())
