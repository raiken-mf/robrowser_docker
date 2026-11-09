#!/usr/bin/env ruby
require 'yaml'
require 'open3'
require 'tmpdir'
require 'fileutils'

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
ci_path = File.expand_path('../../../.github/workflows/ci.yml', __dir__)
ci = YAML.safe_load(File.read(ci_path))
steps = ci.fetch('jobs').fetch('validate').fetch('steps')
scope = steps.find { |step| step['id'] == 'scope' }.fetch('run')
build_line = scope.lines.find { |line| line.include?('grep -Ev') && line.include?('grep -Eq') }
raise 'Missing build scope' unless build_line
patterns = build_line.scan(/grep -E[vq] '([^']+)'/).flatten
raise 'Invalid build scope' unless patterns.length == 2
{
  ['docs/gitops.md'] => false,
  ['deploy/clusters/default/ragnarok-app.yaml'] => false,
  ['deploy/k8s/overlays/flux/kustomization.yaml', 'deploy/overlays/flux/kustomization.yaml'] => false,
  ['clusters/pi-cluster/kustomization.yaml', 'images/robrowser/Dockerfile'] => true,
  ['images/rathena/Dockerfile'] => true,
  ['deploy/k8s/base/rathena.yaml'] => true,
  ['deploy/k8s/overlays/other/kustomization.yaml'] => true
}.each do |paths, expected|
  filtered, filter_status = Open3.capture2('grep', '-Ev', patterns.first, stdin_data: paths.join("\n") + "\n")
  raise 'Invalid exclusion pattern' unless [0, 1].include?(filter_status.exitstatus)
  _, match_status = Open3.capture2('grep', '-Eq', patterns.last, stdin_data: filtered)
  raise "Unexpected build scope for #{paths.inspect}" unless match_status.success? == expected
end
raise 'PR security gate missing' unless ci.fetch('jobs').fetch('validate').fetch('needs') == 'pr-image-security'
%w[Build\ RemoteClient\ for\ smoke\ test Build\ roBrowser\ frontend\ for\ smoke\ test Build\ wsProxy].each do |name|
  step = steps.find { |entry| entry['name'] == name }
  raise "Invalid build condition: #{name}" unless step && step['if'] == "steps.scope.outputs.build == 'true'"
end
rathena = steps.find { |entry| entry['name'] == 'Build rAthena on AMD64 (PR validation)' }
raise 'Invalid rAthena build condition' unless rathena && rathena['if'] == "steps.scope.outputs.rathena == 'true'"
root = File.expand_path('../../..', __dir__)
dependabot = YAML.safe_load(File.read(File.join(root, '.github/dependabot.yml')))
schedule = dependabot.fetch('multi-ecosystem-groups').fetch('dependencies').fetch('schedule')
raise 'Invalid Dependabot schedule' unless schedule == { 'interval' => 'weekly', 'day' => 'monday', 'time' => '12:00', 'timezone' => 'Europe/Berlin' }
updates = dependabot.fetch('updates')
expected = [['github-actions', '/'], ['npm', '/images/robrowser'], ['npm', '/images/wsproxy']] + %w[remote robrowser rathena wsproxy hercules].map { |image| ['docker', "/images/#{image}"] }
raise 'Invalid Dependabot ecosystems' unless updates.map { |entry| [entry.fetch('package-ecosystem'), entry.fetch('directory')] }.sort == expected.sort
raise 'Invalid Dependabot grouping' unless updates.all? { |entry| entry['patterns'] == ['*'] && entry['multi-ecosystem-group'] == 'dependencies' }
security_updates = updates.select { |entry| %w[npm github-actions].include?(entry['package-ecosystem']) }
raise 'Invalid security grouping' unless security_updates.all? { |entry| entry['groups'] == { 'security' => { 'applies-to' => 'security-updates', 'patterns' => ['*'] } } }
updater = YAML.safe_load(File.read(File.join(root, '.github/workflows/dependency-update.yml')))
triggers = updater.fetch('on') { updater.fetch(true) }
raise 'Fork updater must be manual' unless triggers.keys == ['workflow_dispatch']
Dir.mktmpdir('rathena-scope-') do |directory|
  FileUtils.mkdir_p(File.join(directory, 'build'))
  file = File.join(directory, 'build/dependencies.env')
  original = "ROBROWSER_REF=#{'a' * 40}\nRATHENA_REF=#{'b' * 40}\n"
  File.write(file, original)
  system('git', 'init', '-q', directory, out: File::NULL, err: File::NULL) or raise 'Cannot initialize fixture'
  system('git', '-C', directory, 'add', 'build/dependencies.env') or raise 'Cannot stage fixture'
  tree, tree_status = Open3.capture2('git', '-C', directory, 'write-tree')
  raise 'Cannot create fixture tree' unless tree_status.success?
  script = File.join(root, 'scripts/sh/ci/check-rathena-pin-scope.sh')
  { original => true, original.sub('a' * 40, 'c' * 40) => true,
    original.sub('b' * 40, 'c' * 40) => false,
    original + "UNKNOWN_REF=new\n" => false,
    original.sub('a' * 40, 'invalid') => false,
    original.sub('a' * 40, 'c' * 40) + "+RATHENA_REF=invalid\n" => false }.each do |content, expected_result|
    File.write(file, content)
    system('git', '-C', directory, 'add', 'build/dependencies.env') or raise 'Cannot stage fixture'
    result = system('bash', script, tree.strip, chdir: directory, out: File::NULL, err: File::NULL)
    raise "Invalid rAthena pin scope: #{content.inspect}" unless result == expected_result
  end
  raise 'Invalid revision must require a build' if system('bash', script, 'invalid-revision', chdir: directory, out: File::NULL, err: File::NULL)
end
puts 'PASS PR image security matrix and regression fixtures'