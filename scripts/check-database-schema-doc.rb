#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)
DOC_PATH = File.join(ROOT, "docs/engineering/database-schema.md")
APP_PATH = File.join(ROOT, "Soma/App/SomaApp.swift")
MODEL_GLOB = File.join(ROOT, "Soma/Models/**/*.swift")
MIGRATION_GLOB = File.join(ROOT, "Server/migrations/*.sql")

def abort_with(message)
  warn "Database schema documentation check failed: #{message}"
  exit 1
end

def brace_delta(line)
  delta = 0
  quoted = false
  escaped = false
  index = 0

  while index < line.length
    character = line[index]
    next_character = line[index + 1]

    break if !quoted && character == "/" && next_character == "/"

    if quoted
      if escaped
        escaped = false
      elsif character == "\\"
        escaped = true
      elsif character == '"'
        quoted = false
      end
    elsif character == '"'
      quoted = true
    elsif character == "{"
      delta += 1
    elsif character == "}"
      delta -= 1
    end

    index += 1
  end

  delta
end

def swiftdata_models
  models = {}

  Dir.glob(MODEL_GLOB).sort.each do |path|
    lines = File.readlines(path)
    pending_model = false
    current_model = nil
    depth = 0

    lines.each do |line|
      pending_model = true if line.strip == "@Model"

      if pending_model && current_model.nil? && (match = line.match(/\b(?:final\s+)?class\s+(\w+)/))
        current_model = match[1]
        models[current_model] ||= []
        depth = brace_delta(line)
        pending_model = false
        next
      end

      next unless current_model

      code = line.sub(%r{//.*$}, "")
      if depth == 1 && !code.include?("{") &&
          (match = code.match(/^\s*(?:@\w+(?:\([^)]*\))?\s+)?var\s+(\w+)\s*:/))
        models[current_model] << match[1]
      end

      depth += brace_delta(line)
      next unless depth <= 0

      current_model = nil
      depth = 0
    end
  end

  models
end

def registered_swiftdata_models
  source = File.read(APP_PATH)
  schema_body = source[/let schema = Schema\(\[(.*?)\]\)/m, 1]
  return schema_body.scan(/(\w+)\.self/).flatten.sort if schema_body

  versioned_schema = source[/let schema = Schema\(versionedSchema:\s*(\w+)\.self\)/, 1]
  abort_with("cannot find ModelContainer Schema registration in SomaApp.swift") unless versioned_schema

  model_source = Dir.glob(MODEL_GLOB).sort.map { |path| File.read(path) }.join("\n")
  schema_declaration = model_source[/enum\s+#{Regexp.escape(versioned_schema)}\s*:\s*VersionedSchema\s*\{(.*?)\n\}/m, 1]
  abort_with("cannot find VersionedSchema #{versioned_schema}") unless schema_declaration

  models_body = schema_declaration[/static\s+var\s+models\s*:\s*\[any\s+PersistentModel\.Type\]\s*\{\s*\[(.*?)\]\s*\}/m, 1]
  abort_with("cannot find model catalog for VersionedSchema #{versioned_schema}") unless models_body

  models_body.scan(/(\w+)\.self/).flatten.sort
end

def postgres_tables
  tables = {}
  migration_paths = Dir.glob(MIGRATION_GLOB).sort
  migration_names = migration_paths.map { |path| File.basename(path) }
  versioned_names = migration_names.reject { |name| name == "000_schema_migrations.sql" }
  invalid_names = versioned_names.reject { |name| name.match?(/\A[0-9]{3,}_[a-z0-9]+(?:_[a-z0-9]+)*\.sql\z/) }
  abort_with("invalid PostgreSQL migration names: #{invalid_names.join(', ')}") unless invalid_names.empty?

  versions = versioned_names.map { |name| name[/\A([0-9]+)_/, 1].to_i }
  duplicate_versions = versions.group_by { |version| version }.select { |_version, matches| matches.length > 1 }.keys
  abort_with("duplicate PostgreSQL migration versions: #{duplicate_versions.join(', ')}") unless duplicate_versions.empty?
  unless versions.empty?
    expected_versions = (1..versions.max).to_a
    missing_versions = expected_versions - versions
    abort_with("missing PostgreSQL migration versions: #{missing_versions.join(', ')}") unless missing_versions.empty?
  end

  migration_paths.each do |path|
    source = File.read(path)
    source.scan(/CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+([a-z_][a-z0-9_]*)\s*\((.*?)\);/mi) do |name, body|
      columns = body.lines.map do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("--")
        next if stripped.match?(/\A(?:CONSTRAINT|PRIMARY|UNIQUE|CHECK|FOREIGN)\b/i)

        stripped[/\A"?([a-z_][a-z0-9_]*)"?\s+/i, 1]
      end.compact
      tables[name] = columns
    end

    source.scan(/ALTER\s+TABLE(?:\s+IF\s+EXISTS)?\s+(?:ONLY\s+)?([a-z_][a-z0-9_]*)\s+(.*?);/mi) do |name, action|
      abort_with("ALTER TABLE references unknown table #{name} in #{File.basename(path)}") unless tables.key?(name)

      action.scan(/ADD\s+COLUMN(?:\s+IF\s+NOT\s+EXISTS)?\s+"?([a-z_][a-z0-9_]*)"?/i).flatten.each do |column|
        tables[name] << column unless tables[name].include?(column)
      end
      action.scan(/DROP\s+COLUMN(?:\s+IF\s+EXISTS)?\s+"?([a-z_][a-z0-9_]*)"?/i).flatten.each do |column|
        tables[name].delete(column)
      end
      action.scan(/RENAME\s+COLUMN\s+"?([a-z_][a-z0-9_]*)"?\s+TO\s+"?([a-z_][a-z0-9_]*)"?/i).each do |old_name, new_name|
        index = tables[name].index(old_name)
        abort_with("RENAME COLUMN references unknown #{name}.#{old_name}") unless index

        tables[name][index] = new_name
      end
      table_rename = action.match(/\ARENAME\s+TO\s+"?([a-z_][a-z0-9_]*)"?/i)
      next unless table_rename

      new_name = table_rename[1]
      tables[new_name] = tables.delete(name)
    end

    source.scan(/DROP\s+TABLE(?:\s+IF\s+EXISTS)?\s+"?([a-z_][a-z0-9_]*)"?/i).flatten.each do |name|
      tables.delete(name)
    end
  end

  Dir.glob(File.join(ROOT, "Server/src/**/*.ts")).sort.each do |path|
    next unless File.read(path).match?(/\b(?:CREATE|ALTER|DROP)\s+(?:TABLE|TYPE|INDEX)\b/i)

    abort_with("PostgreSQL DDL must live in Server/migrations, found in #{path.delete_prefix(ROOT + '/')}")
  end

  tables
end

def documented_entries(source, kind)
  entries = {}
  source.scan(/<!--\s*schema-#{kind}:\s*([A-Za-z_][A-Za-z0-9_]*)\s*\|\s*([^>]+?)\s*-->/) do |name, fields|
    abort_with("duplicate schema-#{kind} marker for #{name}") if entries.key?(name)

    entries[name] = fields.split(",").map(&:strip).reject(&:empty?)
  end
  entries
end

def compare_catalog(label, actual, documented)
  actual_names = actual.keys.sort
  documented_names = documented.keys.sort
  missing = actual_names - documented_names
  extra = documented_names - actual_names
  abort_with("#{label} missing entries: #{missing.join(', ')}") unless missing.empty?
  abort_with("#{label} has stale entries: #{extra.join(', ')}") unless extra.empty?

  actual_names.each do |name|
    actual_fields = actual.fetch(name).sort
    documented_fields = documented.fetch(name).sort
    next if actual_fields == documented_fields

    missing_fields = actual_fields - documented_fields
    extra_fields = documented_fields - actual_fields
    details = []
    details << "missing fields #{missing_fields.join(', ')}" unless missing_fields.empty?
    details << "stale fields #{extra_fields.join(', ')}" unless extra_fields.empty?
    abort_with("#{label} #{name}: #{details.join('; ')}")
  end
end

abort_with("missing #{DOC_PATH}") unless File.file?(DOC_PATH)

models = swiftdata_models
registered_models = registered_swiftdata_models
model_names = models.keys.sort
unless model_names == registered_models
  missing = model_names - registered_models
  extra = registered_models - model_names
  details = []
  details << "unregistered @Model types #{missing.join(', ')}" unless missing.empty?
  details << "Schema contains unknown types #{extra.join(', ')}" unless extra.empty?
  abort_with(details.join("; "))
end

document = File.read(DOC_PATH)
compare_catalog("SwiftData catalog", models, documented_entries(document, "model"))
tables = postgres_tables
compare_catalog("PostgreSQL catalog", tables, documented_entries(document, "table"))

documented_model_count = document[/注册完全相同的\s*(\d+)\s*个模型/, 1]&.to_i
abort_with("SwiftData model count summary is stale") unless documented_model_count == models.length
documented_table_count = document[/以下\s*(\d+)\s*张表/, 1]&.to_i
abort_with("PostgreSQL table count summary is stale") unless documented_table_count == tables.length

puts "Database schema documentation is synchronized."
