# Importe les nouvelles parties depuis chess.com et lance leur analyse.
# Les mois passés sont immuables : on ne les retélécharge pas s'ils sont déjà en base.
class ImportGamesJob < ApplicationJob
  def perform(user = CHESSCOM_USER, analyze: true)
    api = Chesscom.new(user)
    archives = api.archives
    imported = []

    archives.each_with_index do |url, i|
      year, month = url.split("/").last(2).map(&:to_i)
      month_start = Time.utc(year, month)
      current_month = (i == archives.size - 1)
      next if !current_month && Game.where(played_at: month_start...(month_start + 1.month)).exists?

      api.games(url).each do |data|
        next if Game.exists?(uuid: data["uuid"])
        imported << Game.from_chesscom(data, user).tap(&:save!)
      end
      sleep 0.3 # politesse envers l'API
    end

    imported.sort_by(&:played_at).reverse_each { |g| AnalyzeGameJob.perform_later(g) } if analyze
    imported
  end
end
