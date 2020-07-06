### ZSH ###
alias resource="source ~/.zshrc"

### GIT ####
alias commits="history | grep 'git commit .*ITEM-' | tail -n 5"
alias gits="git status"
alias fixpointers="git lfs uninstall && git reset --hard && git lfs install && git lfs pull"
alias gcmp="git checkout master; git pull"
alias gcaan="git commit -a --amend --no-edit"
alias gls="git log --pretty=oneline --abbrev-commit"
