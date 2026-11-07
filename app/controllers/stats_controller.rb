class StatsController < ApplicationController
  def index
    games = Game.all
    games = games.where(time_class: params[:time_class]) if params[:time_class].present?

    @by_month = games.group_by { |g| g.played_at.strftime("%Y-%m") }
                     .sort.reverse.map { |month, gs| [month, summarize(gs)] }

    @by_opening = games.where.not(opening: nil).group_by(&:opening)
                       .select { |_, gs| gs.size >= 3 }
                       .map { |name, gs| [name, summarize(gs)] }
                       .sort_by { |_, s| -s[:games] }

    @mistakes = Game.analyzed.flat_map { |g| g.moves.select { |m| m["color"] == g.color && m["class"] == "Gaffe" }.map { |m| [g, m] } }
                    .sort_by { |g, _| -g.played_at.to_i }.first(30)
  end

  private

  def summarize(gs)
    analyzed = gs.select(&:analyzed?)
    {
      games:    gs.size,
      wins:     gs.count { |g| g.result == "win" },
      draws:    gs.count { |g| g.result == "draw" },
      accuracy: analyzed.any? ? (analyzed.sum(&:accuracy) / analyzed.size).round(1) : nil,
      blunders: analyzed.any? ? (analyzed.sum { |g| g.counts["Gaffe"].to_i }.to_f / analyzed.size).round(2) : nil,
      rating:   gs.max_by(&:played_at)&.my_rating
    }
  end
end
