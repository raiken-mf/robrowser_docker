#!/usr/bin/env ruby
require 'yaml'

EXPECTED_IMAGES = %w[remote robrowser rathena wsproxy].freeze
EXPECTED_ARCHITECTURES = %w[amd64 arm64].freeze

def validate_matrix(workflow)
  matrix = workflow.fetch('jobs').fetch('scan').fetch('strategy').fetch('matrix')
  { 'image' => EXPECTED_IMAGES, 'arch' => EXPECTED_ARCHITECTURES }.each do |key, expected|
    actual = matrix.fetch(key)
    raise "Invalid #{key} matrix: #{actual.inspect}" unless actual.is_a?(Array) && actual.sort == expected.sort
  end
  raise 'Matrix exclusions are not supported' if matrix.key?('exclude')
  includes = matrix.fetch('include')
  raise 'Invalid matrix runner mappings' unless includes.is_a?(Array) && includes.all? { |entry| entry.is_a?(Hash) && entry.keys.sort == %w[arch runner] }
  runners = includes.map { |entry| [entry.fetch('arch'), entry.fetch('runner')] }
  raise 'Invalid matrix runner mappings' unless runners.sort == [['amd64', 'ubuntu-latest'], ['arm64', 'ubuntu-24.04-arm']]
end

fixture = {
  'jobs' => { 'scan' => { 'strategy' => { 'matrix' => {
    'image' => EXPECTED_IMAGES.reverse,
    'arch' => EXPECTED_ARCHITECTURES.reverse,
    'include' => [
      { 'arch' => 'amd64', 'runner' => 'ubuntu-latest' },
      { 'arch' => 'arm64', 'runner' => 'ubuntu-24.04-arm' }
    ]
  } } } }
}
validate_matrix(fixture)
matrix = fixture.fetch('jobs').fetch('scan').fetch('strategy').fetch('matrix')
[
  matrix.merge('image' => EXPECTED_IMAGES - ['remote']),
  matrix.merge('image' => EXPECTED_IMAGES + ['hercules']),
  matrix.merge('arch' => ['amd64']),
  matrix.merge('arch' => EXPECTED_ARCHITECTURES + ['other']),
  matrix.merge('exclude' => [{ 'image' => 'remote', 'arch' => 'arm64' }]),
  matrix.merge('include' => matrix.fetch('include') + [{ 'image' => 'hercules', 'arch' => 'amd64' }])
].each do |invalid_matrix|
  invalid = { 'jobs' => { 'scan' => { 'strategy' => { 'matrix' => invalid_matrix } } } }
  begin
    validate_matrix(invalid)
  rescue RuntimeError
    next
  end
  raise 'Invalid matrix was accepted'
end

workflow_path = ARGV.fetch(0, File.expand_path('../../../.github/workflows/pr-image-security.yml', __dir__))
validate_matrix(YAML.safe_load(File.read(workflow_path)))
puts 'PASS PR image security matrix and regression fixtures'