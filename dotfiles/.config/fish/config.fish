source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

# opencode
fish_add_path "$HOME/.opencode/bin"

# aliases ported from zshrc
alias code codium
alias list "ls -a"
alias resources btop
alias monitor btop
alias cluade claude
alias calude claude
alias claudio claude
alias v vim
alias vi nvim
alias z zeditor
alias zed zeditor
alias pysource "source .venv/bin/activate.fish"
alias hyprconfig "code ~/.config/hypr"
alias fishconfig "code ~/.config/fish"
alias noctaliasettings "noctalia msg settings-open lockscreen"
alias noctaliaconfig "noctalia msg settings-open lockscreen"
alias music myx   