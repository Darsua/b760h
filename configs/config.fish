# Fish Shell Configuration (~/.config/fish/config.fish)

# UTF-8 locale environment
set -gx LANG C.UTF-8
set -gx LC_ALL C.UTF-8

# Ensure user local bin is in PATH
fish_add_path ~/.local/bin

# Default environment variables
set -gx EDITOR vim
set -gx GOPATH $HOME/.local/share/go
set -gx GOBIN $HOME/.local/bin
set -gx DOCKER_CONFIG $HOME/.config/docker
set -gx NPM_CONFIG_USERCONFIG $HOME/.config/npm/npmrc
set -gx NPM_CONFIG_CACHE $HOME/.cache/npm

# Interactive session setup
if status is-interactive
    # Commands to run in interactive sessions can go here

    # Initialize Starship prompt
    if type -q starship
        starship init fish | source
    end

    # Initialize Zoxide (smart cd)
    if type -q zoxide
        zoxide init fish | source
    end

    # Initialize FZF keybindings (Ctrl+R, Ctrl+T, Alt+C)
    if type -q fzf
        fzf --fish | source
    end

    # Aliases
    if type -q eza
        alias ls="eza --icons=auto"
        alias ll="eza -la --icons=auto --git"
        alias la="eza -a --icons=auto"
        alias lt="eza --tree --level=2 --icons=auto"
    end

    if type -q bat
        alias cat="bat --paging=auto"
    end

    alias grep="grep --color=auto"
end
