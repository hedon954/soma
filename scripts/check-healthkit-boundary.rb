#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
root = Pathname.new(__dir__).parent
reader_path = root.join("Soma/Services/Health/HealthKitDailyActivityReader.swift")
body_reader_path = root.join("Soma/Services/Health/HealthKitBodyMassReader.swift")
reader = reader_path.read
body_reader = body_reader_path.read
failures = []
types = reader.scan(/HKQuantityType\(\.(\w+)\)/).flatten.uniq.sort
failures << "HealthKit quantities must be steps, walking/running distance, active energy and body mass only" unless
  types == %w[activeEnergyBurned bodyMass distanceWalkingRunning stepCount]
failures << "Minimal workout identity and interval reading must be declared" unless reader.include?("types.insert(HKObjectType.workoutType())")
failures << "HealthKit must remain read-only" unless reader.include?("requestAuthorization(toShare: [], read: Self.readTypes)")
failures << "Body mass reader must remain read-only" unless body_reader.include?("requestAuthorization(toShare: [], read: [Self.bodyMassType])")
failures << "Body mass reader must only declare bodyMass" unless body_reader.scan(/HKQuantityType\(\.(\w+)\)/).flatten.uniq.sort == %w[bodyMass]
# ADR 0144: daily totals use system-merged sumQuantity().
# ADR 0146: sumQuantity(for:) allowed only for separateBySource Contribution packaging.
failures << "HealthKit sources must not be added to the daily total" if reader.include?("sumQuantity(for:") &&
  !(reader.include?("separateBySource") && reader.include?("DailyActivitySourceContribution"))
failures << "Daily totals must still use system-merged sumQuantity()" unless reader.include?("sumQuantity()?.doubleValue")
allowed_adapters = [reader_path, body_reader_path]
Dir[root.join("Soma/**/*.swift")].each do |path|
  pathname = Pathname.new(path)
  next if allowed_adapters.include?(pathname)
  failures << "HealthKit adapter escaped into #{path}" if File.read(path).match?(/^import HealthKit$/)
end
connection = root.join("Soma/Services/Health/HealthConnectionStore.swift").read
store = root.join("Soma/Models/SomaStoreOpening.swift").read
failures << "HealthKit storage protection or backup exclusion was removed" unless
  connection.include?(".completeFileProtection") && store.include?("FileProtectionType.complete") && store.include?("isExcludedFromBackup = true")
%w[DataBackupService.swift DataExportService.swift].each do |name|
  failures << "Health activity must stay out of backup and export" unless root.join("Soma/Services/Media", name).read.include?("withoutHealthActivity()")
end
failures << "withoutHealthActivity must also filter imported body mass" unless
  root.join("Soma/Services/Media/DataArchiveModels.swift").read.include?("bodyEntries.removeAll")
failures << "Daily activity must be a record, not a separate dashboard card" if root.join("Soma/Views/DailyActivityCard.swift").exist?
plist = root.join("Soma/Resources/Info.plist").read
failures << "HealthKit read purpose is missing" unless plist.include?("NSHealthShareUsageDescription")
failures << "HealthKit read purpose must mention body weight" unless plist.include?("体重")
failures << "HealthKit writes or mandatory hardware were enabled" if plist.include?("NSHealthUpdateUsageDescription") || plist.include?("<string>healthkit</string>")
if failures.empty?
  puts "HealthKit read-only projection boundary passed."
else
  abort failures.join("
")
end
