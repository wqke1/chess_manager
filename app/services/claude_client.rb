require "net/http"
require "json"

# Client minimal pour l'API Claude (messages). Clé : ENV["ANTHROPIC_API_KEY"].
class ClaudeClient
  URL = URI("https://api.anthropic.com/v1/messages")

  def self.ask(system:, messages:, max_tokens: 700)
    key = ENV["ANTHROPIC_API_KEY"] or raise "ANTHROPIC_API_KEY manquante (export ANTHROPIC_API_KEY=sk-ant-... avant de lancer le serveur)"
    req = Net::HTTP::Post.new(URL, "content-type" => "application/json",
                                   "x-api-key" => key, "anthropic-version" => "2023-06-01")
    req.body = { model: CLAUDE_MODEL, max_tokens: max_tokens, system: system, messages: messages }.to_json
    res = Net::HTTP.start(URL.host, URL.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
    body = JSON.parse(res.body)
    raise "Claude #{res.code} : #{body.dig('error', 'message') || res.body[0, 200]}" unless res.is_a?(Net::HTTPSuccess)
    body["content"].map { |c| c["text"] }.compact.join
  end
end
