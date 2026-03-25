# Homebrew formula for Budget Guard.
# Tap: dalex160/budget-guard
# Install: brew tap dalex160/budget-guard && brew install budget-guard
#
# SwiftBar runs plugins from ~/Library/Application Support/SwiftBar/Plugins/.
# Homebrew's sandbox prevents writing there during post_install, so we ship
# a "budget-guard-link" helper that the user runs once after install.
class BudgetGuard < Formula
  desc "SwiftBar plugin showing Claude Max usage in the macOS menu bar"
  homepage "https://github.com/dalex160/claude-budget-watch"
  url "https://github.com/dalex160/claude-budget-watch/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "bcd6ea26668de0ad5b6861867d9a45e4a8aa32b8ebbd0d9bffbffbc43b0b0926"
  license "MIT"

  depends_on :macos
  depends_on "python@3"

  def install
    bin.install "budget-guard.2m.sh"

    # Resolve bin path at runtime so the symlink survives prefix changes
    (bin/"budget-guard-link").write <<~SH
      #!/bin/bash
      set -euo pipefail
      PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
      mkdir -p "$PLUGINS_DIR"
      ln -sf "$(brew --prefix)/bin/budget-guard.2m.sh" "$PLUGINS_DIR/budget-guard.2m.sh"
      echo "Linked budget-guard into SwiftBar plugins directory."
      if ! pgrep -x SwiftBar >/dev/null 2>&1; then
        echo "Starting SwiftBar..."
        open -a SwiftBar 2>/dev/null || echo "SwiftBar not found. Install it: brew install --cask swiftbar"
      else
        echo "SwiftBar is running. The plugin will appear on next refresh."
      fi
    SH
    (bin/"budget-guard-link").chmod 0755
  end

  def caveats
    <<~EOS
      To complete setup, run:
        budget-guard-link

      This links the plugin into SwiftBar's plugin directory and starts SwiftBar.

      Prerequisites:
        - SwiftBar must be installed: brew install --cask swiftbar
        - Claude Code must have been authenticated at least once (OAuth token in Keychain)

      To enable debug logging:
        export BUDGET_GUARD_DEBUG=1

      Logs: ~/.claude/budget-guard.log
    EOS
  end

  test do
    assert_predicate bin/"budget-guard.2m.sh", :executable?
    assert_match "#!/bin/bash", (bin/"budget-guard.2m.sh").read.lines.first
  end
end
