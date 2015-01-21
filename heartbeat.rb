#!/usr/bin/env ruby
#
# Opsgenie handler which sends heartbeats
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
        response = send_heartbeat
        if response['code'] == 200
          puts 'opsgenie -- heartbeat sent'
        else
          puts 'opsgenie -- failed to send heartbeat'
        end
      end
    rescue Timeout::Error
      puts 'opsgenie -- timed out while attempting to send heartbeat'
    end
  end

  def send_heartbeat
    params = {}

    client_name = @event['client']['name']
    unless client_name =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
      client_name = client_name.split('.').first
    end
    params['name'] = client_name
    params['apiKey'] = settings['opsgenie']['apiKey']

    uri = URI.parse('https://api.opsgenie.com/v1/json/heartbeat/send')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Post.new(uri.request_uri, {'Content-Type' =>'application/json'})
    request.body = params.to_json
    response = http.request(request)
    JSON.parse(response.body)
  end

end
