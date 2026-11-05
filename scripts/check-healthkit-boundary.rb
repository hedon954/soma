#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
root = Pathname.new(__dir__).parent
reader_path = root.join("Soma/Services/Health/HealthKitDailyActivityReader.swift")
reader = reader_path.read
failures = []
types = reader.scan(/HKQuantityType\(\.(\w+)\)/).flatten.uniq.sort
failures << "HealthKit quantities must be steps, walking/running distance and active energy only" unless
  types == %w[activeEnergyBurned distanceWalkingRunning stepCount]
failures << "Minimal workout identity and interval reading must be declared" unless reader.include?("types.insert(HKObjectType.workoutType())")
failures << "HealthKit must remain read-only" unless reader.include?("requestAuthorization(toShare: [], read: Self.readTypes)")
# ADR 0144: daily totals use system-merged sumQuantity().
# ADR 0146: sumQuantity(for:) allowed only for separateBySource Contribution packaging.
failures << "HealthKit sources must not be added to the daily total" if reader.include?("sumQuantity(for:") &&
  !(reader.include?("separateBySource") && reader.include?("DailyActivitySourceContribution"))
failures << "Daily totals must still use system-merged sumQuantity()" unless reader.include?("sumQuantity()?.doubleValue")
Dir[root.join("Soma/**/*.swift")].each do |path|
  next if Pathname.new(path) == reader_path
  failures << "HealthKit adapter escaped into #{path}" if File.read(path).match?(/^import HealthKit$/)
end
connection = root.join("Soma/Services/Health/HealthConnectionStore.swift").read
store = root.join("Soma/Models/SomaStoreOpening.swift").read
failures << "HealthKit storage protection or backup exclusion was removed" unless
  connection.include?(".completeFileProtection") && store.include?("FileProtectionType.complete") && store.include?("isExcludedFromBackup = true")
%w[DataBackupService.swift DataExportService.swift].each do |name|
  failures << "Health activity must stay out of backup and export" unless root.join("Soma/Services/Media", name).read.include?("withoutHealthActivity()")
end
failures << "Daily activity must be a record, not a separate dashboard card" if root.join("Soma/Views/DailyActivityCard.swift").exist?
plist = root.join("Soma/Resources/Info.plist").read
failures << "HealthKit read purpose is missing" unless plist.include?("NSHealthShareUsageDescription")
failures << "HealthKit writes or mandatory hardware were enabled" if plist.include?("NSHealthUpdateUsageDescription") || plist.include?("<string>healthkit</string>")
if failures.empty?
  puts "HealthKit read-only projection boundary passed."
else
  abort failures.join("\n")
end
