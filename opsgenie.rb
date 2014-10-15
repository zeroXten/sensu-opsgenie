#!/usr/bin/env ruby
#
# Opsgenie handler which creates and closes alerts.
# Modified from the sensu community plugin

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-handler'
require "net/https"
require "uri"
require "json"
require "time"

class Opsgenie < Sensu::Handler

  def handle
    begin
      timeout(3) do
        response = case @event['action']
                   when 'create'
                     create_alert
                   when 'resolve'
                     close_alert
                   end
        if response['code'] == 200
          puts 'opsgenie -- ' + @event['action'].capitalize + 'd incident -- ' + event_id
        else
          puts 'opsgenie -- failed to ' + @event['action'] + ' incident -- ' + event_id
        end
      end
    rescue Timeout::Error
      puts 'opsgenie -- timed out while attempting to ' + @event['action'] + ' a incident -- ' + event_id
    end
  end

  def event_id
    @event['client']['name'] + '/' + @event['check']['name']
  end

  def event_status
    @event['check']['status']
  end

  def close_alert
    post_to_opsgenie(:close, {:alias => event_id})
  end

  def create_alert
    post_body = {
      :alias => event_id,
    }

    client_name = @event['client']['name']
    unless client_name =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
      client_name = client_name.split('.').first
    end
    post_body[:message] = "#{@event['check']['output']} on #{client_name}"

    tags = @event['check']['tags'] || []
    tags << settings["opsgenie"]["tags"] if settings["opsgenie"]["tags"]
    tags << "OverwriteQuietHours" if event_status == 2 && settings["opsgenie"]["overwrite_quiet_hours"] == true
    tags << "unknown" if event_status >= 3
    tags << "critical" if event_status == 2
    tags << "warning" if event_status == 1
    tags << client_name
    post_body[:tags] = tags.join(",")

    post_body[:description] = @event['check']['description'] || ''

    if @event['check']['command']
      command_translations = {}
      command = @event['check']['command']
      command.scan(/:::(.*?):::/).map do |c|
        command_translations[c.first] = c.first.split('.').inject(@event['client'], :fetch)
      end
      command_translations.each_pair do |name, value|
        command.gsub!(":::#{name}:::", value)
      end
    else
      command = "no command"
    end

    post_body[:details] = {
      :output => @event['check']['output'],
      :client => @event['client']['name'],
      :client_ip => @event['client']['address'],
      :issued => Time.at(@event['check']['issued']),
      :command => command
    }
    post_to_opsgenie(:create, post_body)
  end

  def post_to_opsgenie(action = :create, params = {})
    params["customerKey"] = settings["opsgenie"]["customerKey"]
    params["recipients"]  = settings["opsgenie"]["recipients"]

    # override source if specified, default is ip
    params["source"] = settings["opsgenie"]["source"] if settings["opsgenie"]["source"]

    uripath = (action == :create) ? "" : "close"
    uri = URI.parse("https://api.opsgenie.com/v1/json/alert/#{uripath}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Post.new(uri.request_uri, {'Content-Type' =>'application/json'})
    request.body = params.to_json
    response = http.request(request)
    JSON.parse(response.body)
  end

end
