#!/usr/bin/env ruby

# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)

def count(path, pattern)
  File.read(File.join(ROOT, path)).scan(pattern).length
end

def fail_check(message)
  warn "Performance hot-path check failed: #{message}"
  exit 1
end

SERVICE_FILES = Dir.glob(File.join(ROOT, "Soma/Services/**/*.swift")).each_with_object({}) do |path, acc|
  name = File.basename(path)
  fail_check("duplicate Soma/Services basename #{name}") if acc.key?(name)
  acc[name] = path.delete_prefix("#{ROOT}/")
end

def service_file(name)
  SERVICE_FILES.fetch(name) { fail_check("missing Soma/Services/**/#{name}") }
end

# These ceilings capture the audited baseline. Every remediation must lower the
# corresponding value; new regressions fail immediately even before all legacy
# occurrences have been removed.
ceilings = {
  ["Soma/Views/RootView.swift", /@Query/] => 0,
  ["Soma/Views/CoachView.swift", /@Query/] => 3,
  ["Soma/Views/InsightsView.swift", /@Query/] => 3,
  ["Soma/Views/SettingsView.swift", /@Query/] => 3,
  ["Soma/Views/TrainingProgramViews.swift", /@Query/] => 14,
  ["Soma/Views/HistoryViews.swift", /@Query/] => 0,
  ["Soma/Views/RecordDetailViews.swift", /@Query/] => 0,
  ["Soma/Views/ConversationSessionViews.swift", /@Query/] => 0,
  ["Soma/Views/ExerciseViews.swift", /@Query/] => 1,
  ["Soma/Views/CoachView.swift", /UIImage\(data:/] => 0,
  ["Soma/Views/FeedbackView.swift", /UIImage\(data:/] => 0,
  ["Soma/Components/DesignSystem.swift", /MediaStore\.image\(at:/] => 0,
  ["Soma/Components/ExerciseArtworkView.swift", /MediaStore\.image\(at:/] => 0,
  ["Soma/Components/ExerciseArtworkView.swift", /UIImage\(contentsOfFile:/] => 0,
  ["Soma/Components/MediaViewer.swift", /MediaStore\.image\(at:/] => 0,
  ["Soma/Components/StoredMediaStrip.swift", /MediaStore\.image\(at:/] => 0,
  ["Soma/Components/MediaPicker.swift", /if let data = image\.jpegData/] => 0,
  [service_file("GuidedWorkoutCoordinator.swift"), /FetchDescriptor<(WorkoutSession|ExercisePerformance|WorkoutSet|WorkoutEffort)>\(\)/] => 0,
  [service_file("GuidedWorkoutCoordinator+Timeline.swift"), /FetchDescriptor<(WorkoutSession|ExercisePerformance|WorkoutSet|WorkoutEffort)>\(\)/] => 0,
  [service_file("GuidedWorkoutCoordinator+Recording.swift"), /FetchDescriptor<(WorkoutSession|ExercisePerformance|WorkoutSet|WorkoutEffort)>\(\)/] => 0,
  [service_file("ConversationSessionDeletion.swift"), /FetchDescriptor<[^>]+>\(\)/] => 0,
  [service_file("ConversationProcessingQueueActions.swift"), /FetchDescriptor<(AgentJob|CoachMessage|PersistentAgentEvent|AgentTrace)>\(\)/] => 0,
  [service_file("GuidedWorkoutRecordStore.swift"), /FetchDescriptor<(WorkoutEntry|ExerciseDefinition|WorkoutSet|WorkoutEffort)>\(\)/] => 0,
  ["Soma/Views/WorkoutShareViews.swift", /FetchDescriptor<(ExercisePerformance|WorkoutSet|ExerciseDefinition|WorkoutEntry)>\(\)/] => 0,
  [service_file("ConversationCompactionMiddleware.swift"), /FetchDescriptor<(CoachMessage|ConversationCompactionSummary)>\(\)/] => 0,
  [service_file("ConversationProcessingRemoteTrace.swift"), /FetchDescriptor<(CoachMessage|AgentTrace)>\(\)/] => 0,
  [service_file("ConversationRecorderTrainingPlans.swift"), /FetchDescriptor<(TrainingProgram|WorkoutSession|ExercisePerformance|PerformanceAnalysis|AgentJob|ExerciseDefinition)>\(\)/] => 0,
  [service_file("ConversationRecorderTrainingQueries.swift"), /FetchDescriptor<(ExercisePerformance|WorkoutSet|ExerciseDefinition)>\(\)/] => 0,
  [service_file("AgentContextPackBuilder.swift"), /FetchDescriptor<ExerciseDefinition>\(\)/] => 0,
  ["Soma/Models/ExerciseDefinition.swift", /FetchDescriptor<[^>]+>\(\)/] => 2
}

ceilings.each do |(path, pattern), maximum|
  actual = count(path, pattern)
  next if actual <= maximum

  fail_check("#{path} has #{actual} occurrences of #{pattern.inspect}; ceiling is #{maximum}")
end

root_source = File.read(File.join(ROOT, "Soma/Views/RootView.swift"))
fail_check("RootView restored observable pending tab state") if root_source.include?("pendingTabTransition")
unless root_source.include?("AppTabReselect.effect")
  fail_check("RootView no longer separates tab selection from stack reset")
end
modern_tabs = root_source[/private var modernRootTabs: some View \{(.*?)\n    private var legacyRootTabs/m, 1].to_s
unless root_source.include?("if #available(iOS 18.0, *)") &&
       modern_tabs.scan(/\bTab\(/).length == 4 &&
       modern_tabs.include?("value: AppTab.coach") &&
       modern_tabs.include?("Tab(\"训练\", systemImage: \"dumbbell\", value: AppTab.training)") &&
       modern_tabs.include?("value: AppTab.insights") &&
       modern_tabs.include?("Tab(\"设置\", systemImage: \"gearshape\", value: AppTab.settings)")
  fail_check("current iOS restored the legacy tabItem path instead of native Tab content")
end
if root_source.include?("StableRootTabContent")
  fail_check("Root Tab content restored the wrapper that can collapse native Tab items")
end
if root_source.match?(/\.onAppear\s*\{\s*completeTabTransition/)
  fail_check("Tab signpost completion again competes with the selection commit frame")
end
unless root_source.include?("private struct RootTabVisibilityReporter") &&
       root_source.scan(/RootTabVisibilityReporter\(tab:/).length == 4 &&
       root_source.match?(/RootTabVisibilityReporter.*?await Task\.yield\(\).*?contentDidBecomeVisible/m)
  fail_check("Tab content signpost no longer uses one stable leaf reporter per Tab")
end
unless %w[CoachRootTab TrainingRootTab InsightsRootTab SettingsRootTab].all? do |name|
         root_source.include?("private struct #{name}: View")
       end
  fail_check("Root restored one composite view tree instead of four persistent Tab roots")
end
unless root_source.match?(/case \.noAction:.*?break/m) &&
       root_source.match?(/case let \.switchTo\(tab\):.*?selectedTab = tab/m) &&
       root_source.match?(/case let \.resetStack\(tab\):.*?tabStackIDs\[tab\] = UUID\(\)/m) &&
       root_source.match?(
         /RootTabReselectObserver\(\s*onReselect: handleTabReselect,\s*onDoubleReselect: handleTabDoubleReselect\s*\)/m
       ) &&
       root_source.include?("tabNavigation.isAtRoot(selectedTab)")
  fail_check("Tab selection or root-aware reselect lost its single bounded effect")
end
if root_source.include?("tabStackIDs[.coach]") || root_source.include?(".coach: UUID()")
  fail_check("coach reselect can again rebuild the whole conversation tree via a stack identity reset")
end
if root_source.match?(/CoachRootTab\([^)]*(sheet|isActive)/m)
  fail_check("CoachRootTab again receives per-render inputs that invalidate the hidden coach subtree")
end
unless root_source.include?(".environment(\\.coachTabIsActive, selectedTab == .coach)")
  fail_check("coach tab activity no longer flows through the leaf-only environment key")
end
unless root_source.include?("for: .coachRequiresAIConfiguration")
  fail_check("the AI-configuration sheet lost its stable notification path from the coach subtree")
end
tab_performance_source = File.read(File.join(ROOT, service_file("AppPerformance.swift")))
unless tab_performance_source.include?("final class AppTabTransitionCoordinator")
  fail_check("Tab transition signpost coordinator was removed")
end
if root_source.include?("setAnimationsEnabled") ||
   tab_performance_source.include?("setAnimationsEnabled") ||
   root_source.include?("commitSelectionWithoutContentCrossfade") ||
   tab_performance_source.include?("commitSelectionWithoutContentCrossfade")
  fail_check("Tab selection globally suppresses UIKit animations")
end
if root_source.include?("AppTabBarResolver") ||
   tab_performance_source.include?("removeAnimationsRecursively")
  fail_check("measured-no-value Tab bar layer traversal was restored")
end
fail_check("RootView restored selection-dependent tab symbols") if root_source.include?("systemImage: selectedTab")
unless root_source.include?("guard didFinishInitialMaintenance else { return }")
  fail_check("RootView can again duplicate foreground recovery during initial maintenance")
end
foreground_block = root_source[/\.onChange\(of: scenePhase\).*?else if scenePhase == \.background/m]
if foreground_block&.include?("conversationSessions.resolveForEntry")
  fail_check("foreground entry can again switch and rebuild the visible coach Session")
end
unless root_source.include?(".foregroundRecovery")
  fail_check("foreground recovery lost its dedicated performance interval")
end

coach_source = File.read(File.join(ROOT, "Soma/Views/CoachView.swift"))
coach_actions_source = File.read(File.join(ROOT, "Soma/Views/CoachSessionView+Actions.swift"))
coach_screen_source = "#{coach_source}\n#{coach_actions_source}"
coach_support_source = File.read(File.join(ROOT, "Soma/Views/CoachMessagePerformanceSupport.swift"))
coach_view_support_source = File.read(File.join(ROOT, "Soma/Views/CoachViewSupport.swift"))
coach_bubble_source = File.read(File.join(ROOT, "Soma/Views/CoachBubble.swift"))
chat_record_source = File.read(File.join(ROOT, "Soma/Views/ChatRecordEditorCards.swift"))
coach_response_source = File.read(File.join(ROOT, "Soma/Components/CoachResponseView.swift"))
selectable_chat_source = File.read(File.join(ROOT, "Soma/Components/SelectableChatText.swift"))
agent_transcript_source = File.read(File.join(ROOT, "Soma/Views/AgentTurnTranscript.swift"))
incremental_chat_text_source = File.read(File.join(ROOT, "Soma/Components/IncrementalChatTextView.swift"))
device_tab_profile_source = File.read(File.join(ROOT, "scripts/profile-device-tab-loop.sh"))
device_profile_source = File.read(File.join(ROOT, "scripts/profile-device-harness.sh"))
device_profile_core_source = File.read(File.join(ROOT, "scripts/profile-device-performance.sh"))
device_install_source = File.read(File.join(ROOT, "scripts/install-device.sh"))
device_install_stamp_source = File.read(File.join(ROOT, "scripts/record-device-install-stamp.sh"))
processing_models_source = File.read(File.join(ROOT, service_file("ConversationProcessingModels.swift")))
unless device_tab_profile_source.include?('exec "$root_dir/scripts/profile-device-harness.sh"')
  fail_check("legacy physical-device profiler no longer forwards to the canonical harness")
end
if device_profile_source.include?("xcodebuild") ||
   device_profile_source.include?("make install-device") &&
     !device_profile_source.include?("Run once:")
  fail_check("canonical physical-device profiling can again build or install implicitly")
end
unless device_profile_source.include?("device-app-fingerprint.sh") &&
       device_profile_source.include?("Formal recording attempt") &&
       device_profile_source.include?("reset_instruments_helper") &&
       device_profile_source.include?('SOMA_PROFILE_ATTACH="$app_pid"') &&
       device_profile_source.include?("SOMA_DEVICE_PERFORMANCE_WAIT_FOR_FIXTURE_COMPLETION") &&
       device_profile_core_source.include?("SOMA_PROFILE_START_TIMEOUT_SECONDS") &&
       device_profile_core_source.include?('status="start_timed_out"') &&
       device_profile_core_source.include?('status="record_failed_after_start"') &&
       device_install_source.include?("record-device-install-stamp.sh") &&
       device_install_stamp_source.include?('$2 == "deviceIdentifier:" && !found { print $3')
  fail_check("reusable physical-device profiling lost its install stamp, exact PID, or fast-fail gate")
end
device_fingerprint_source = File.read(File.join(ROOT, "scripts/device-app-fingerprint.sh"))
unless device_fingerprint_source.include?("git ls-files --cached --others --exclude-standard") &&
       device_fingerprint_source.include?('[[ ! -f "$path" ]]') &&
       !device_fingerprint_source.include?("rg --files Soma SomaWidget")
  fail_check("device build fingerprint can again include ignored credentials or tracked deletions")
end
if coach_response_source.include?("MarkdownText(") ||
   selectable_chat_source.include?("struct SelectableChatText: UIViewRepresentable") ||
   selectable_chat_source.match?(/func makeUIView.*?UITextView/m)
  fail_check("chat text restored per-block TextKit views on the Tab transition path")
end
unless coach_response_source.include?("CoachTextRenderCache.completedText(for: markdown)") &&
       coach_response_source.include?("Task.detached(priority: .userInitiated)") &&
       coach_response_source.include?("CompletedChatTextView(render: completedText)") &&
       !coach_response_source.include?("ForEach(document.blocks.indices") &&
       incremental_chat_text_source.include?("render.measuredHeight(") &&
       incremental_chat_text_source.include?("render.storeMeasuredHeight(") &&
       selectable_chat_source.include?("CoachTextRenderCache.attributedText(for: content)") &&
       coach_response_source.include?("totalCostLimit") &&
       root_source.include?("CoachTextRenderCache.removeAll()")
  fail_check("completed chat text no longer reuses bounded render projections")
end
if coach_source.include?("recentExerciseCapacities") || coach_source.include?("@Query(sort: \\ExerciseDefinition")
  fail_check("CoachView restored render-path exercise aggregation")
end
if coach_source.include?("agentJobs.first { $0.responseMessageID == message.id }")
  fail_check("Coach message rows restored one linear AgentJob lookup per bubble")
end
unless coach_source.include?("visibility.autoScrollGate.shouldScroll(to: messageID)")
  fail_check("Coach can again force a full scroll-to-bottom layout on every Tab reentry")
end
unless coach_source.include?(
  "@State private var messageLimit = CoachMessagePagePolicy.pageSize"
) &&
       coach_source.include?(
         "messageLimit = CoachMessagePagePolicy.nextLimit(after: messageLimit)"
       ) &&
       coach_source.include?(".id(conversationSessions.activeSessionID)") &&
       coach_support_source.include?("static let pageSize = 10")
  fail_check("Coach message paging no longer matches the stable product baseline")
end
unless coach_support_source.include?("jobByResponseMessageID")
  fail_check("Coach message rows no longer share one AgentJob index per render")
end
unless coach_bubble_source.include?("CoachMessageRenderPayloadCache.payload(for: message)") &&
       !coach_source.include?("CoachMessageRenderPayloadCache.payload(for:") &&
       coach_support_source.include?("private static let countLimit = 64")
  fail_check("Coach render cache no longer stays bounded to bubbles the user actually viewed")
end
unless chat_record_source.include?(".task(id: recordID)") &&
       chat_record_source.include?("await Task.yield()")
  fail_check("chat record cards no longer defer their bounded lookup until a visible card appears")
end
if coach_source.include?("ConversationTurnProjection.canRetry(")
  fail_check("Coach message rows restored one full turn scan per bubble")
end
unless coach_source.include?("retryableMessageIDs.contains(message.id)") &&
       coach_support_source.include?("retryableMessageIDs")
  fail_check("Coach message rows no longer share one retryable-message set per render")
end
if coach_source.include?(".onChange(of: processor.liveAssistantText)") ||
   coach_source.include?(".onChange(of: processor.liveAgentActivity)")
  fail_check("Coach restored redundant live-stream observation at the screen root")
end
unless coach_source.scan(/processor\.liveEventRevision/).empty?
  fail_check("Coach screen root again observes the high-frequency live stream revision")
end
unless agent_transcript_source.match?(/struct StreamingAgentTextView.*?IncrementalChatTextView/m) &&
       incremental_chat_text_source.include?("view.textStorage.append") &&
       incremental_chat_text_source.include?("func sizeThatFits(") &&
       processing_models_source.include?("static let defaultTargetCharacterCount = 256") &&
       processing_models_source.include?("targetCharacterCount - chunks[chunks.count - 1].text.count")
  fail_check("long-stream text can again remeasure a large eager stack or unbounded mutable tail")
end
unless coach_support_source.include?("struct CoachLiveAutoScrollDriver: View") &&
       coach_support_source.include?("processor.liveEventRevision") &&
       coach_actions_source.include?("targetMessageID: UUID? = nil") &&
       coach_actions_source.include?("proxy.scrollTo(targetMessageID, anchor: .bottom)") &&
       coach_source.include?("targetMessageID: message.id")
  fail_check("live coach output no longer follows the stable message bottom independently of lazy rows")
end
if coach_source.include?("@State private var isCoachVisible") ||
   coach_source.match?(/\.onAppear\s*\{[^}]*refreshInputShortcuts/m)
  fail_check("Coach appearance again writes observable visibility or decodes shortcuts in the Tab commit frame")
end
if coach_source.match?(/@State[^\n]*AgentInputShortcutStore\.visibleShortcuts/) ||
   !coach_source.include?("@State private var inputShortcuts: [AgentInputShortcut] = []")
  fail_check("Coach View construction again synchronously decodes shortcut JSON")
end
unless coach_view_support_source.include?("speechInput ?? SpeechInputService()") &&
       !coach_screen_source.include?("SpeechInputService()")
  fail_check("Coach again constructs speech services before the first voice action")
end
if coach_source.match?(/@State[^\n]*\b(draft|attachments|speechInput|useLocalForNextMessage)\b/)
  fail_check("composer state returned to the session page and every keystroke can again rebuild the chat tree")
end
composer_views_source = File.read(File.join(ROOT, "Soma/Views/CoachComposerViews.swift"))
unless coach_view_support_source.include?("final class CoachComposerState") &&
       composer_views_source.include?("@Bindable var state: CoachComposerState") &&
       coach_source.include?("state: composer,")
  fail_check("the composer no longer isolates draft, attachments, and dictation behind one observable state object")
end
if coach_source.include?("GeometryReader") ||
   coach_source.include?("sessionDrawerGesture(drawerWidth:")
  fail_check("Coach root again makes every update depend on drawer geometry")
end
unless coach_source.include?("CoachVisibilityState") &&
       coach_source.match?(/\.task\s*\{.*?await Task\.yield\(\).*?refreshInputShortcuts\(\)/m) &&
       coach_source.include?(".agentInputShortcutsDidChange")
  fail_check("Coach appearance no longer defers secondary work until after Tab selection commits")
end
unless coach_source.match?(/AVAudioSession 停用.*?await Task\.yield\(\).*?speechInput\.stop\(\)/m)
  fail_check("Coach disappearance can again synchronously deactivate audio in the Tab commit frame")
end
if coach_source.include?("isTabActive")
  fail_check("Coach screen again plumbs tab activity through view parameters instead of the leaf environment key")
end
unless coach_source.match?(/\.equatable\(\)\s*\n\s*\.id\(message\.id\)/m) &&
       coach_bubble_source.include?("struct CoachBubble: View, Equatable") &&
       coach_bubble_source.include?("static func == (lhs: CoachBubble, rhs: CoachBubble)")
  fail_check("message rows no longer skip parent-driven diffing through Equatable bubbles")
end
if coach_screen_source.match?(/@State[^\n]*(lastLiveScrollAt|liveScrollTask)/)
  fail_check("live scroll throttling again writes observable @State on every streaming tick")
end
unless coach_view_support_source.include?("final class CoachLiveScrollThrottle") &&
       coach_actions_source.include?("visibility.liveScroll")
  fail_check("live scroll throttling no longer lives on the non-observed holder")
end
unless coach_support_source.include?("struct CoachTabActivationDriver") &&
       coach_support_source.scan(/@Environment\(\\\.coachTabIsActive\)/).length == 2 &&
       coach_source.include?("CoachTabActivationDriver {")
  fail_check("switching to the coach tab no longer returns to the latest message through one leaf driver")
end
unless agent_transcript_source.include?('@Environment(\.coachTabIsActive) private var observesLiveText')
  fail_check("the live transcript observer no longer gates streaming observation by tab activity")
end
if coach_source.include?("coachTabReselected") ||
   coach_support_source.include?("coachTabReselected") ||
   root_source.include?("restoreCoachRoot")
  fail_check("coach reselect restored a notification or navigation side effect")
end

coach_snapshot_source = File.read(File.join(ROOT, service_file("CoachSuggestionSnapshot.swift")))
if coach_snapshot_source.include?("performanceDescriptor.fetchLimit = 400") ||
   coach_snapshot_source.include?("setDescriptor.fetchLimit = 1500") ||
   !coach_snapshot_source.include?(".flatMap(\\.performances)") ||
   !coach_snapshot_source.include?(".flatMap(\\.workoutSets)")
  fail_check("Coach suggestions restored global child-table scans instead of recent sessions")
end

insights_source = File.read(File.join(ROOT, "Soma/Views/InsightsView.swift"))
fail_check("InsightsView restored on-appear revision polling") if insights_source.include?("refreshRevision")
if insights_source.match?(/\.onAppear\s*\{[^}]*requestSnapshotIfNeeded\(\)/m) ||
   !insights_source.match?(/\.task\s*\{.*?await Task\.yield\(\).*?requestSnapshotIfNeeded\(\)/m)
  fail_check("Insights snapshot request again competes with the Tab selection commit frame")
end
if insights_source.include?("equipmentDescriptor") || insights_source.include?("definitionDescriptor")
  fail_check("Insights snapshot restored materializing full equipment or exercise objects for counts")
end
if insights_source.include?("performanceDescriptor.fetchLimit = 2000") ||
   insights_source.include?("setDescriptor.fetchLimit = 5000") ||
   !insights_source.include?(".flatMap(\\.performances)") ||
   !insights_source.include?(".flatMap(\\.workoutSets)")
  fail_check("Insights restored global child-table scans instead of the bounded session graph")
end
unless insights_source.match?(/currentEquipmentCount.*?modelContext\.fetchCount/m) &&
       insights_source.match?(/activeExerciseCount.*?modelContext\.fetchCount/m)
  fail_check("Insights snapshot no longer uses count-only queries for count-only metrics")
end
if insights_source.include?("points.map(\\.volume).max()") ||
   (insights_source.include?("TrainingVolumeTrendCard") &&
    !insights_source.include?("private var periodSummary:"))
  fail_check("scrolling a training chart again allocates or scans the series repeatedly per body")
end

deduper_source = File.read(File.join(ROOT, service_file("AgentBusinessKeyDeduper.swift")))
unless deduper_source.match?(/FetchDescriptor<WorkoutEntry>.*?exerciseID.*?date >= day.*?date < nextDay/m) &&
       deduper_source.match?(/FetchDescriptor<MealEntry>.*?date >= day.*?date < nextDay.*?calories/m) &&
       deduper_source.match?(/FetchDescriptor<BodyEntry>.*?externalSource == nil.*?date >= day.*?date < nextDay/m)
  fail_check("business-key deduplication again materializes complete record tables")
end

agent_job_source = File.read(File.join(ROOT, "Soma/Models/AgentJob.swift"))
claim_next_source = agent_job_source[/static func claimNext\((.*?)\n    static func claim\(/m, 1].to_s
unless claim_next_source.include?("$0.dataSpaceRaw == dataSpaceRaw") &&
       claim_next_source.include?("$0.stateRaw != completed") &&
       claim_next_source.include?("descriptor.fetchLimit = 1")
  fail_check("local job claiming again fetches the full AgentJob table before choosing one row")
end

health_import_source = File.read(File.join(ROOT, service_file("HealthKitImporter.swift")))
if health_import_source.include?("existingWorkouts") ||
   health_import_source.include?("existingBodyEntries")
  fail_check("HealthKit import again loads every prior record from one source")
end
unless health_import_source.match?(/FetchDescriptor<WorkoutEntry>.*?externalSource == source.*?externalID == externalID/m) &&
       health_import_source.match?(/FetchDescriptor<BodyEntry>.*?externalSource == source.*?externalID == externalID/m)
  fail_check("HealthKit import no longer performs exact external-source identity lookups")
end

settings_source = File.read(File.join(ROOT, "Soma/Views/SettingsView.swift"))
fail_check("SettingsView restored root trace counting") if settings_source.include?("AgentTraceCountLabel")
if settings_source.include?("ai.hasRequiredAPIKey")
  fail_check("Settings root can again synchronously read Keychain on first selection")
end
if settings_source.include?("@State private var modelTier") ||
   settings_source.include?("@FocusState private var modelFieldFocused") ||
   !settings_source.include?("LLMConfigurationView(")
  fail_check("Settings root again owns unopened LLM configuration state")
end
unless settings_source.include?("DeferredSettingsFeedbackView()") &&
       settings_source.match?(/if didLoad\s*\{\s*FeedbackView\(isEmbedded: true\)/m) &&
       settings_source.match?(/DeferredSettingsFeedbackView.*?await Task\.yield\(\)/m)
  fail_check("Settings root again mounts the full feedback editor in the selection commit frame")
end

llm_settings_source = File.read(File.join(ROOT, "Soma/Views/LLMConfigurationView.swift"))
unless llm_settings_source.include?("struct LLMConfigurationView: View") &&
       llm_settings_source.include?("SettingsLLMConfigurationDraft.load") &&
       !llm_settings_source.include?(".onAppear(perform: loadInitialConfiguration)") &&
       llm_settings_source.match?(/\.task\s*\{.*?await Task\.yield\(\).*?loadInitialConfiguration\(\)/m)
  fail_check("LLM configuration state is no longer isolated to its destination")
end

shortcut_settings_source = File.read(File.join(ROOT, "Soma/Views/AgentInputShortcutSettingsViews.swift"))
if shortcut_settings_source.include?(".onAppear(perform: reload)") ||
   !shortcut_settings_source.include?("await refreshAfterTransition()") ||
   !shortcut_settings_source.include?("Task.detached(priority: .userInitiated)")
  fail_check("shortcut JSON decoding returned to the settings navigation commit frame")
end

skill_settings_source = File.read(File.join(ROOT, "Soma/Views/AgentPromptSkillSettingsViews.swift"))
if skill_settings_source.include?(".onAppear(perform: reload)") ||
   !skill_settings_source.include?("await refreshAfterTransition()") ||
   !skill_settings_source.include?("Task.detached(priority: .userInitiated)")
  fail_check("Skill JSON decoding returned to the settings navigation commit frame")
end

unless settings_source.match?(/DeveloperSettingsView.*?await refreshSummaryAfterTransition\(\).*?Task\.detached\(priority: \.userInitiated\)/m)
  fail_check("advanced-settings summary decoding returned to the navigation commit frame")
end

ai_profiles_source = File.read(File.join(ROOT, service_file("AIModelProfiles.swift")))
unless ai_profiles_source.include?("warmRequiredAPIKeyCache")
  fail_check("Settings can again perform an uncached Keychain lookup on first Tab selection")
end

save_impact_source = File.read(File.join(ROOT, service_file("ModelContextSaveImpact.swift")))
unless save_impact_source.include?("entities.contains($0.entityName)")
  fail_check("save notifications again resolve every unrelated Agent model on the MainActor")
end

queue_actions_source = File.read(File.join(ROOT, service_file("ConversationProcessingQueueActions.swift")))
if queue_actions_source.include?("AgentJobStore.promoteFailedResponsesToManualRetry")
  fail_check("foreground queue recovery restored a duplicate failed-response scan")
end

agent_job_source = File.read(File.join(ROOT, "Soma/Models/AgentJob.swift"))
unless agent_job_source.match?(/recoverExpiredLeases.*?fetchLimit = 1/m) &&
       agent_job_source.match?(/resumeForegroundJobs.*?fetchLimit = 1/m) &&
       agent_job_source.match?(/promoteFailedResponsesToManualRetry.*?fetchLimit = 1/m)
  fail_check("foreground Agent recovery is no longer bounded to the FIFO head")
end

stream_deadline_source = File.read(File.join(ROOT, service_file("AgentStreamDeadline.swift")))
if stream_deadline_source.match?(/@MainActor\s+static func consume/) ||
   !stream_deadline_source.include?(
     "onChunk: @MainActor (ChatCompletionChunkObject) async throws -> Bool"
   ) ||
   !stream_deadline_source.include?("_ = try await onChunk(chunk)")
  fail_check("raw Agent stream reading or MainActor projection isolation regressed")
end

streaming_source = File.read(File.join(ROOT, service_file("AgentStreamWorker.swift")))
pump_source = File.read(File.join(ROOT, service_file("AgentTextProjectionPump.swift")))
unless streaming_source.include?("enum AgentStreamWorker") &&
       streaming_source.include?("project: @escaping @MainActor (AgentTraceEvent) -> Void") &&
       streaming_source.include?("let projectionPump = AgentTextProjectionPump") &&
       streaming_source.include?("await projectionPump.append(content)") &&
       streaming_source.include?("await projectionPump.finish()") &&
       pump_source.include?("minimumInterval: Duration = .milliseconds(200)") &&
       pump_source.include?("private var drainTask: Task<Void, Never>?")
  fail_check("local stream parsing no longer uses a non-main single-flight projection pump")
end

coalescer_source = File.read(File.join(ROOT, service_file("AgentTextDeltaCoalescer.swift")))
unless coalescer_source.include?("minimumInterval: TimeInterval = 0.2")
  fail_check("visible Agent text projection exceeded the audited 5 Hz budget")
end

agent_job_source = File.read(File.join(ROOT, "Soma/Models/AgentJob.swift"))
delta_projection = agent_job_source[/case \.assistantTextDelta:.*?case let \.assistantTextCompleted/m]
unless delta_projection&.include?("return") &&
       !delta_projection.include?("responseMessage.applyAgentEvent") &&
       !delta_projection.include?("try? context.save()")
  fail_check("every text delta can again rewrite SwiftData and the full transcript JSON")
end

processing_source = File.read(File.join(ROOT, service_file("ConversationProcessingService.swift")))
processing_live_source = File.read(File.join(ROOT, service_file("ConversationTurnLiveProjection.swift")))
processing_models_source = File.read(File.join(ROOT, service_file("ConversationProcessingModels.swift")))
if processing_source.match?(/private\(set\) var liveAssistantText\s*=/) ||
   processing_models_source.include?("private(set) var text = \"\"")
  fail_check("live stream again stores duplicate full growing strings beside stable chunks")
end
unless processing_live_source.include?("projectRemoteTextDelta") &&
       processing_live_source.include?("liveAssistantRenderSnapshot") &&
       processing_models_source.match?(/var text: String\s*\{.*?chunks\.map/m)
  fail_check("live text no longer keeps one chunk source of truth and a render-only snapshot")
end

remote_projection_source = File.read(File.join(ROOT, service_file("ConversationProcessingRemoteTrace.swift")))
unless remote_projection_source.include?("if !event.isTransientTextUpdate") &&
       remote_projection_source.include?("var isTransientTextUpdate: Bool")
  fail_check("remote text deltas can again save their cursor and SwiftData event one by one")
end

transcript_source = File.read(File.join(ROOT, "Soma/Views/AgentTurnTranscript.swift"))
chat_presentation_source = File.read(File.join(ROOT, service_file("AgentChatPresentation.swift")))
if coach_screen_source.include?("AgentTurnLiveProjection.make") ||
   transcript_source.include?("streamingChunks")
  fail_check("live text again builds and sanitizes one full growing AgentTurnItem per UI tick")
end
unless coach_actions_source.include?("let interval: TimeInterval = 0.2") &&
       transcript_source.include?("struct LiveAgentTurnTranscriptContent") &&
       transcript_source.scan(/processor\.liveEventRevision/).length == 1 &&
       transcript_source.include?("struct CoachLiveAgentTurnTranscript") &&
       transcript_source.include?("StreamingAgentTextView(chunks: liveText.chunks)") &&
       chat_presentation_source.include?("enum AgentTurnLiveProjection")
  fail_check("running text no longer renders directly from stable chunks")
end

shortcut_source = File.read(File.join(ROOT, service_file("AgentInputShortcut.swift")))
unless shortcut_source.include?("AgentInputShortcutMemoryCache") &&
       shortcut_source.include?("agentInputShortcutsDidChange")
  fail_check("Coach shortcut JSON can again be decoded on every Tab appearance")
end

media_preparation_source = File.read(File.join(ROOT, service_file("ConversationMediaPreparation.swift")))
unless media_preparation_source.include?("nonisolated func prepareStoredMedia")
  fail_check("Agent media preparation can again synchronously read files on MainActor")
end

guided_record_source = File.read(File.join(ROOT, service_file("GuidedWorkoutRecordStore.swift")))
if guided_record_source.include?("let sets = performance.workoutSets") ||
   guided_record_source.include?("sets.flatMap(\\.efforts)") ||
   guided_record_source.include?("guard let definition = performance.exerciseDefinition") ||
   guided_record_source.include?("if let existing = performance.projectedWorkout")
  fail_check("guided workout materialization restored relationship reads")
end
unless guided_record_source.include?("$0.performanceID == performanceID") &&
       guided_record_source.include?("$0.workoutSetID == setID") &&
       guided_record_source.include?("$0.id == exerciseID")
  fail_check("guided workout materialization no longer walks the scalar ID graph")
end

share_source = File.read(File.join(ROOT, "Soma/Views/WorkoutShareViews.swift"))
if share_source.include?("FetchDescriptor")
  fail_check("workout share restored database fetches instead of the current relationship graph")
end
unless share_source.include?("Task.detached(priority: .userInitiated)")
  fail_check("workout share PNG encoding returned to MainActor")
end

calorie_source = File.read(File.join(ROOT, service_file("WorkoutCalorieCalculator.swift")))
unless calorie_source.include?("bodyDescriptor.fetchLimit = 50") &&
       !calorie_source.include?("profileDescriptor")
  fail_check("latest recorded weight lookup is no longer date-filtered and bounded")
end

crash_source = File.read(File.join(ROOT, service_file("CrashDiagnosticsCoordinator.swift")))
diagnostic_store_source = File.read(File.join(ROOT, service_file("DiagnosticReportStore.swift")))
unless crash_source.include?("await reports.pendingReportsAsync()") &&
       diagnostic_store_source.include?("cachedReports")
  fail_check("startup diagnostics can again repeatedly decode large reports on MainActor")
end

diagnostic_settings_source = File.read(File.join(ROOT, "Soma/Views/DiagnosticReportSettingsView.swift"))
diagnostic_log_source = File.read(File.join(ROOT, service_file("DiagnosticsLogStore.swift")))
if diagnostic_settings_source.include?(".onAppear(perform: reload)") ||
   !diagnostic_settings_source.include?("recentTextAsync()") ||
   !diagnostic_settings_source.include?("latestReportTextAsync()") ||
   !diagnostic_log_source.include?("func recentTextAsync")
  fail_check("diagnostic file reads returned to the settings navigation commit frame")
end

training_source = File.read(File.join(ROOT, "Soma/Views/TrainingProgramViews.swift"))
if training_source.include?(".performanceFingerprint(for: performance)")
  fail_check("training video hashing returned to the MainActor view path")
end
if training_source.include?("TrainingPlanStore.summary")
  fail_check("training session summaries returned to repeated SwiftUI render paths")
end
unless training_source.include?("TrainingProgramStatsSnapshotLoader")
  fail_check("training program statistics no longer use a background snapshot")
end
if training_source.match?(/ForEach\(prescriptions\.sorted/)
  fail_check("training program detail again sorts stable prescriptions in every body update")
end

training_store_source = File.read(File.join(ROOT, service_file("TrainingPlanStore.swift")))
summary_section = training_store_source[/static func summary\(.*?\n    static func deleteSession/m]
if summary_section&.match?(/FetchDescriptor<(ExercisePerformance|WorkoutSet|WorkoutEffort|WorkoutEntry)>/)
  fail_check("current training summary restored per-relation compatibility fetches")
end

history_source = File.read(File.join(ROOT, "Soma/Views/HistoryViews.swift"))
if history_source.include?("@Query(sort: \\ExerciseDefinition.canonicalName)")
  fail_check("workout history restored a full exercise-library query")
end

record_source = File.read(File.join(ROOT, "Soma/Views/RecordDetailViews.swift"))
if record_source.include?("@Query(sort: \\ExerciseDefinition.canonicalName)")
  fail_check("workout record detail restored a full exercise-library query")
end
unless record_source.include?(".task(id: date)")
  fail_check("workout editor can again query reference weight from every body render")
end

gym_source = File.read(File.join(ROOT, "Soma/Views/GymViews.swift"))
if gym_source.include?("allEquipment") || gym_source.include?("allMedia")
  fail_check("gym detail restored cross-gym equipment or media reads")
end

exercise_editor_source = File.read(File.join(ROOT, "Soma/Views/ExerciseDetailEditors.swift"))
unless exercise_editor_source.include?("mergeDescriptor.fetchLimit = 1")
  fail_check("exercise merge undo query is no longer bounded to the latest record")
end

conversation_sessions_source = File.read(File.join(ROOT, "Soma/Views/ConversationSessionViews.swift"))
unless conversation_sessions_source.include?("descriptor.fetchLimit = sessionLimit + 1")
  fail_check("conversation drawer no longer paginates session history")
end

agent_projection_source = File.read(File.join(ROOT, "Soma/Views/AgentSystemProjectionHost.swift"))
if agent_projection_source.include?("modelContext.fetchCount")
  fail_check("root agent projection restored MainActor event counting")
end
unless agent_projection_source.include?("Task.sleep(for: .milliseconds(100))")
  fail_check("root agent projection no longer coalesces high-frequency job revisions")
end

exercise_detail_source = File.read(File.join(ROOT, "Soma/Views/ExerciseViews.swift"))
unless exercise_detail_source.include?("affectsExerciseHistory")
  fail_check("exercise history restored refreshes for every database save")
end
unless exercise_detail_source.include?("ExerciseDetailHistoryProjection(") &&
       !exercise_detail_source.include?("private var allHistory:") &&
       !exercise_detail_source.include?("private var displayedVolumeTrend:")
  fail_check("exercise detail again rebuilds the same history and trend projection several times per body")
end

session_source = File.read(File.join(ROOT, "Soma/Models/ConversationSession.swift"))
if session_source.include?("FetchDescriptor<CoachMessage>(\n                    sortBy:")
  fail_check("conversation entry restored a full chat-history fetch")
end
unless session_source.include?("latestMessageDescriptor.fetchLimit = 1")
  fail_check("conversation entry no longer resolves from a bounded latest message")
end
if exercise_detail_source.include?("private struct ExerciseLibraryRow: View {\n    @Query")
  fail_check("exercise library restored one live workout query per row")
end

speech_source = File.read(File.join(ROOT, service_file("SpeechInputService.swift")))
if speech_source.match?(/private (?:let|var) recognizer\s*=\s*SFSpeechRecognizer/) ||
   speech_source.match?(/private (?:let|var) audioEngine\s*=\s*AVAudioEngine\(\)/)
  fail_check("speech recognition resources are initialized before the first voice action")
end

training_home_source = File.read(File.join(ROOT, "Soma/Views/TrainingHomeComponents.swift"))
if training_home_source.scan(/session\.performances\.sorted/).length > 1 ||
   training_home_source.include?("private var orderedPerformances")
  fail_check("training resume card again sorts the same relationship for every derived label")
end

guided_workout_source = File.read(File.join(ROOT, "Soma/Views/GuidedWorkoutView.swift"))
guided_snapshot_source = File.read(
  File.join(ROOT, service_file("GuidedWorkoutScreenSnapshot.swift"))
)
if guided_workout_source.include?("@Query private var allPerformances") ||
   guided_workout_source.include?("@Query private var allSets") ||
   guided_workout_source.include?("@Query private var allEfforts") ||
   guided_workout_source.include?("$0.performance?.sessionID") ||
   guided_workout_source.include?("$0.workoutSet?.performance?.sessionID")
  fail_check("guided workout restored SwiftData relationship queries in its render path")
end
unless guided_workout_source.include?("let sessionID: UUID") &&
       guided_workout_source.include?("GuidedWorkoutScreenSnapshotLoader.load") &&
       guided_snapshot_source.include?("$0.sessionID == sessionID") &&
       guided_snapshot_source.include?("$0.performanceID == performanceID") &&
       guided_snapshot_source.include?("$0.workoutSetID == setID")
  fail_check("guided workout no longer renders from a scalar-ID immutable snapshot")
end
if training_source.include?("$0.performance?.sessionID == sessionID") ||
   training_source.include?("$0.workoutSet?.performance?.sessionID == sessionID")
  fail_check("training review restored a multi-relationship SwiftData predicate")
end

footprints_source = File.read(File.join(ROOT, "Soma/Views/FootprintsView.swift"))
unless footprints_source.include?("@State private var snapshot = FootprintsSnapshot(messages: [])") &&
       footprints_source.include?("private static let pageSize = 40") &&
       footprints_source.match?(/\.task\s*\{.*?await Task\.yield\(\).*?loadMore\(\)/m)
  fail_check("footprints again rebuilds an unbounded projection in body or fetches 100 rows during navigation")
end

history_source = File.read(File.join(ROOT, "Soma/Views/HistoryViews.swift"))
if history_source.match?(/\.onAppear\s*\{\s*if (?:loaded|entries)\.isEmpty/m) ||
   history_source.scan(/await Task\.yield\(\)/).length < 3
  fail_check("history destinations again fetch their first page in the navigation commit frame")
end

startup_maintenance = [
  "finalizeInterruptedAgentTraces",
  "backfillConversationTurns",
  "mergeObviousDuplicateRecords",
  "removeUnsupportedInferences",
  "migrateLegacyWorkoutSets",
  "migrateLegacyWorkoutNames",
  "activateBundledContent",
  "GuidedWorkoutRecordStore.backfill"
]

startup_count = startup_maintenance.count { |name| root_source.include?(name) }
fail_check("RootView added a new startup maintenance scan") if startup_count > 2

view_sources = Dir.glob(File.join(ROOT, "Soma/{App,Views,Components}/**/*.swift"))
string_revisions = view_sources.select do |path|
  File.read(path).match?(/(?:var|let)\s+\w*[Rr]evision\s*:\s*String/)
end
unless string_revisions.empty?
  fail_check("string revisions remain in render paths: #{string_revisions.join(', ')}")
end

puts "Performance hot-path baseline passed."
