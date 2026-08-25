#!/usr/bin/env bash
set -euo pipefail

REQUEST_DIR="${1:-02-accounts-creation}"
REPORT_PATH="${VALIDATION_REPORT_PATH:-account-reports/validation.json}"
mkdir -p "$(dirname "$REPORT_PATH")"

export REQUEST_DIR REPORT_PATH

ruby <<'RUBY'
require "json"
require "yaml"
require "open3"

request_dir = ENV.fetch("REQUEST_DIR")
report_path = ENV.fetch("REPORT_PATH")
errors = []
requests = []
emails = {}
required = %w[account_name email managed_org_unit owner environment cost_center regions tags]
environments = %w[dev development test staging qa prod production sandbox]

files = Dir.glob(File.join(request_dir, "*.yaml")).sort
files.each do |file|
  begin
    data = YAML.safe_load(File.read(file), permitted_classes: [], aliases: false)
  rescue StandardError => e
    errors << { "file" => file, "error" => "invalid_yaml: #{e.message}" }
    next
  end
  unless data.is_a?(Hash)
    errors << { "file" => file, "error" => "request must be a mapping" }
    next
  end

  missing = required.reject { |key| data.key?(key) }
  missing.each { |key| errors << { "file" => file, "error" => "missing_required_field: #{key}" } }
  next unless missing.empty?

  unless data["email"].is_a?(String) && data["email"].match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
    errors << { "file" => file, "error" => "invalid_email" }
  end
  email = data["email"].to_s.downcase
  if emails.key?(email)
    errors << { "file" => file, "error" => "duplicate_email: #{email} (also #{emails[email]})" }
  else
    emails[email] = file
  end
  unless data["environment"].is_a?(String) && environments.include?(data["environment"].downcase)
    errors << { "file" => file, "error" => "invalid_environment" }
  end
  unless data["regions"].is_a?(Array) && data["regions"].all? { |region| region.is_a?(String) && !region.empty? }
    errors << { "file" => file, "error" => "regions_must_be_a_list_of_strings" }
  end
  unless data["tags"].is_a?(Hash) && data["tags"].all? { |key, value| key.is_a?(String) && value.is_a?(String) }
    errors << { "file" => file, "error" => "tags_must_be_a_map_of_strings" }
  end
  requests << data.merge("_file" => file)
end

ignored_file = File.join(request_dir, ".ignored-accounts.yaml")
ignored = if File.file?(ignored_file)
  YAML.safe_load(File.read(ignored_file), permitted_classes: [], aliases: false)
else
  []
end
unless ignored.is_a?(Array) && ignored.all? { |entry| entry.is_a?(Hash) && entry["email"].is_a?(String) && entry["reason"].is_a?(String) && !entry["reason"].empty? }
  errors << { "file" => ignored_file, "error" => "ignored_accounts_must_be_a_list_of_email_reason_mappings" }
  ignored = []
end
ignored_emails = ignored.map { |entry| entry["email"].downcase }

accounts = []
require_aws = ENV["VALIDATE_ACCOUNTS_REQUIRE_AWS"] == "1" || ENV["CI"] == "1"
if system("command -v aws >/dev/null 2>&1")
  raw, status = Open3.capture2("aws", "organizations", "list-accounts", "--output", "json")
  if status.success?
    begin
      accounts = JSON.parse(raw).fetch("Accounts", [])
    rescue JSON::ParserError => e
      errors << { "error" => "invalid_organizations_response: #{e.message}" }
    end
  elsif require_aws
    errors << { "error" => "aws organizations list-accounts failed" }
  end
elsif require_aws
  errors << { "error" => "aws cli not available" }
end

represented = emails.keys
accounts.each do |account|
  email = account["Email"].to_s.downcase
  unless represented.include?(email) || ignored_emails.include?(email)
    errors << { "error" => "unmanaged_account: #{account["Id"]} #{account["Email"]}" }
  end
end

account_by_email = accounts.to_h { |account| [account["Email"].to_s.downcase, account] }
requests.each do |request|
  account = account_by_email[request["email"].to_s.downcase]
  next unless account
  if account["Name"] && account["Name"] != request["account_name"]
    errors << { "file" => request["_file"], "error" => "immutable_identity_mismatch: account_name" }
  end
end

report = {
  "status" => errors.empty? ? "valid" : "invalid",
  "request_count" => requests.length,
  "aws_account_count" => accounts.length,
  "errors" => errors
}
File.write(report_path, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
exit(errors.empty? ? 0 : 1)
RUBY
