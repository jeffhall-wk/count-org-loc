# frozen_string_literal: true

require 'octokit'
require 'open3'
require 'cliver'
require 'fileutils'
require 'dotenv'

if ARGV.count != 1
  puts 'Usage: script/count [ORG NAME]'
  exit 1
end

Dotenv.load

def cloc(*args)
  cloc_path = Cliver.detect! 'cloc'
  Open3.capture2e(cloc_path, *args)
end

tmp_dir = File.expand_path './tmp', File.dirname(__FILE__)
FileUtils.rm_rf tmp_dir
FileUtils.mkdir_p tmp_dir

# Enabling support for GitHub Enterprise
unless ENV['GITHUB_ENTERPRISE_URL'].nil?
  Octokit.configure do |c|
    c.api_endpoint = ENV['GITHUB_ENTERPRISE_URL']
  end
end

client = Octokit::Client.new access_token: ENV['GITHUB_TOKEN']
client.auto_paginate = true

repos = client.organization_repositories(ARGV[0].strip, type: 'sources')
puts "Found #{repos.count} repos. Counting..."

reports = []
repos.each do |repo|

  # skip if the repo is archived
  next if repo.archived

  # also skip if repo hasn't been updated in the last 2 years
  start_time = DateTime.strptime(repo.updated_at, '%Y-%m-%dT%H:%M:%SZ')
  end_time = DateTime.now
  next if (end_time - start_time) > 2*365

  puts "Counting #{repo.name}..."

  destination = File.expand_path repo.name, tmp_dir
  report_file = File.expand_path "#{repo.name}.txt", tmp_dir

  clone_url = repo.clone_url
  clone_url = clone_url.sub '//', "//#{ENV['GITHUB_TOKEN']}:x-oauth-basic@" if ENV['GITHUB_TOKEN']
  _output, status = Open3.capture2e 'git', 'clone', '--depth', '1', '--quiet', clone_url, destination
  next unless status.exitstatus.zero?

  _output, _status = cloc destination, '--quiet', "--report-file=#{report_file}"
  reports.push(report_file) if File.exist?(report_file) && status.exitstatus.zero?
end

puts 'Done. Summing...'

output, _status = cloc '--sum-reports', *reports
puts output.gsub(%r{^#{Regexp.escape tmp_dir}/(.*)\.txt}) { Regexp.last_match(1) + ' ' * (tmp_dir.length + 5) }
