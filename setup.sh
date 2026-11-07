#!/usr/bin/env bash
# Installation complète sur Ubuntu (WSL2 ou autre). Une seule commande :
#   curl -sL https://raw.githubusercontent.com/wqke1/chess_manager/main/setup.sh | bash
set -e
echo "== Paquets système (Ruby, Stockfish, SQLite) =="
sudo apt-get update -qq
sudo apt-get install -y -qq git stockfish build-essential libsqlite3-dev libyaml-dev ruby-full ruby-dev pkg-config

echo "== Code =="
cd "$HOME"
if [ -d chess_manager/.git ]; then (cd chess_manager && git pull -q); else git clone -q https://github.com/wqke1/chess_manager.git; fi
cd chess_manager

echo "== Gems =="
export GEM_HOME="$HOME/.gems"; export PATH="$GEM_HOME/bin:$PATH"
grep -q 'GEM_HOME' "$HOME/.bashrc" || echo 'export GEM_HOME="$HOME/.gems"; export PATH="$GEM_HOME/bin:$PATH"' >> "$HOME/.bashrc"
gem install -q --no-document bundler
bundle config set --local path "$GEM_HOME"
bundle install --quiet

echo "== Base =="
bin/rails db:migrate

echo
echo "Installation terminée. Pour lancer le site :"
echo "  cd ~/chess_manager && bin/rails server"
echo "puis ouvre http://localhost:3000 dans ton navigateur Windows."
echo "Pour analyser les parties restantes : bin/rails analyze[6]"
