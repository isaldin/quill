cask "quill" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/isaldin/quill/releases/download/v#{version}/Quill-#{version}.zip"
  name "Quill"
  desc "Menu bar dictation with LLM post-processing via OpenRouter"
  homepage "https://github.com/isaldin/quill"

  depends_on macos: :sequoia

  app "Quill.app"

  uninstall quit: "dev.saldin.quill"

  zap trash: [
    "~/Library/Application Support/Quill",
    "~/Library/Preferences/dev.saldin.quill.plist",
  ]

  caveats <<~EOS
    Quill is not notarized, so macOS blocks the first launch. Run once:
      xattr -dr com.apple.quarantine #{appdir}/Quill.app
  EOS
end
