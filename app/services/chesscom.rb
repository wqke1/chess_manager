require "net/http"
require "json"

# Client minimal pour l'API publique chess.com (lecture seule, pas de clé).
class Chesscom
  BASE = "https://api.chess.com/pub/player"
  UA   = "chess-manager/0.1 (perso)"

  def initialize(user) = @user = user

  # Liste des URLs d'archives mensuelles, de la plus ancienne à la plus récente.
  def archives = get("#{BASE}/#{@user}/games/archives")["archives"]

  # Toutes les parties d'un mois (url d'archive renvoyée par #archives).
  def games(archive_url) = get(archive_url)["games"]

  private

  def get(url)
    res = Net::HTTP.get_response(URI(url), { "User-Agent" => UA })
    raise "chess.com #{res.code} sur #{url}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end
end
