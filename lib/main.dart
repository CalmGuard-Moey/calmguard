import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vibration/vibration.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CalmGuardApp());
}

class CalmGuardApp extends StatelessWidget {
  const CalmGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalmGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const CalmGuardHome(),
    );
  }
}

enum AlertStage {
  monitoring,
  warning,
  triggered,
}

class CalmGuardDebugLog {
  final DateTime time;
  final String event;
  final String details;

  const CalmGuardDebugLog({
    required this.time,
    required this.event,
    required this.details,
  });
}

class CalmGuardHome extends StatefulWidget {
  const CalmGuardHome({super.key});

  @override
  State<CalmGuardHome> createState() => _CalmGuardHomeState();
}

class _CalmGuardHomeState extends State<CalmGuardHome>
    with WidgetsBindingObserver {
  final FlutterTts flutterTts = FlutterTts();
  final stt.SpeechToText speech = stt.SpeechToText();
  final SmartTriggerEngine engine = SmartTriggerEngine();
  final VoiceBehaviourEngine voiceEngine = VoiceBehaviourEngine();

  AlertStage stage = AlertStage.monitoring;

  String appStatus = 'Monitoring';
  String triggerReason = 'All signals normal';
  String heardText = 'No voice sample yet';
  String patternStatus = 'No escalation pattern';
  String setupStatus = 'Setup check not completed';
  String privacyStatus = 'Audio is used for short voice checks only in this prototype';

  final List<CalmGuardDebugLog> debugLogs = [];

  int watchHeartRate = 72;

  // Manual risk test input. This is NOT Samsung stress.
  // It is only used for testing or future real-stress integration.
  int stressLevel = 20;

  // Raw voice level from mic/manual test panel.
  double voiceLevel = 8.0;

  // Voice AI v2 behaviour score. This is not keyword based.
  // It detects loudness spikes, sudden changes, repeated bursts, and sustained intensity.
  double voiceAiScore = 0.0;
  int voiceSpikesLastMinute = 0;
  String voiceBehaviourStatus = 'Voice calm';
  double voiceContextScore = 0.0;
  String voiceContextStatus = 'No concerning words detected';
  DateTime? lastVoiceContextTime;
  DateTime? lastVoiceDecayLogTime;
  String lastProcessedVoiceText = '';
  DateTime? lastProcessedVoiceTextTime;
  String lastConversationRiskCategory = 'calm';
  double voiceConfidenceScore = 0.0;
  bool nativePendingPullSupported = true;
  DateTime? lastNativePendingPullTime;
  DateTime? lastAutoVoiceCheckTime;
  Timer? voiceDebounceTimer;
  String pendingVoiceText = '';
  DateTime? lastSelfVoiceLogTime;
  String lastSelfVoiceText = '';
  bool smartVoiceSessionActive = false;
  DateTime? smartVoiceSessionEndTime;

  // CalmGuard Escalation Risk result.
  // This is calculated from HR baseline deviation + HR trend + Voice AI + pattern.
  double liveStressScore = 20.0;
  int aiStressLevel = 20;
  int warningPatternScore = 0;

  DateTime? lastHeartRateUpdate;
  DateTime? lastTriggerTime;
  DateTime? lastWarningTime;
  DateTime? uiWarningHoldStart;
  DateTime? cooldownEndTime;

  double smoothedWatchStress = 20.0;
  double personalHrBaseline = 72.0;
  int personalHrBaselineSamples = 0;

  bool speechEnabled = false;
  bool isListening = false;
  bool warning = false;
  bool triggered = false;
  bool autoVoiceWindowsEnabled = false;
  bool testPanelExpanded = true;
  bool isSpeaking = false;
  bool isAppInForeground = true;
  bool voiceWatchMode = false;
  bool stopVoiceWatchRequested = false;
  bool allowVoiceCheck = false;
  bool ttsReady = false;
  bool phoneMicAutoDisabled = true;
  bool cooldownActive = false;
  bool recoveryActive = false;
  DateTime? recoveryEndTime;

  bool deepOrangeActive = false;
  DateTime? deepOrangeStart;

  Timer? evaluationTimer;
  Timer? voiceWindowTimer;
  Timer? evaluationDebounceTimer;
  Timer? warningAutoCalmTimer;
  Timer? orangeVoiceRecheckTimer;

  // ORANGE voice sampling rules. CalmGuard is selective, not always listening.
  static const int orangeVoiceWindowSeconds = 20;
  static const int orangeVoiceRecheckDelaySeconds = 25;
  static const int maxOrangeVoiceChecksPerEvent = 3;

  int orangeVoiceChecksThisEvent = 0;
  bool orangeVoiceSamplingActive = false;
  bool orangeWatchReassessmentAllowed = false;
  bool orangeSessionLocked = false;
  bool redRecoveryMessagePlayed = false;

  // Best-effort phone-screen/background monitoring flag.
  // True background reliability still depends on Android foreground service + permissions.
  bool keepMonitoringWhenScreenLocked = true;

  // Manual test guard: Simulate Warning should test ORANGE recovery only.
  // It must not immediately escalate to RED while we are testing warning recovery.
  bool manualWarningTestActive = false;
  DateTime? manualWarningTestUntil;

  static const MethodChannel platform = MethodChannel('calmguard/watch');
  static const MethodChannel voicePlatform = MethodChannel('calmguard/voice');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    resetLocalState(resetEngineToo: true, resetSignals: true);

    platform.setMethodCallHandler((call) async {
      if (call.method == 'onWatchHeartRate') {
        final heartRate = (call.arguments as num).toInt();
        updateHeartRateFromWatch(heartRate);
      } else if (call.method == 'onWatchStressLevel') {
        final stress = (call.arguments as num).toInt();
        updateStressFromWatch(stress);
      } else if (call.method == 'onWatchWarning') {
        simulateWarning();
      } else if (call.method == 'onWatchTrigger') {
        simulateTrigger();
      } else if (call.method == 'onWatchReset') {
        resetSignals();
      }
    });

  voicePlatform.setMethodCallHandler((call) async {
    if (call.method == 'onNativeVoicePartial') {
    final text = (call.arguments ?? '').toString().trim();
    if (text.isNotEmpty) {
      setState(() => heardText = text);
      processVoiceText(text);
    }
  } else if (call.method == 'onNativeVoiceResult') {
    final text = (call.arguments ?? '').toString().trim();
    if (text.isNotEmpty) {
      setState(() => heardText = text);
      processVoiceText(text);
    }
  } else if (call.method == 'onNativeVoiceLevel') {
    final level = (call.arguments as num).toDouble();
    processVoiceLevel(normalizeVoiceLevel(level));
  } else if (call.method == 'onWatchVoiceStarted') {
    addDebugLog('Watch voice started', 'Watch is beginning voice recognition');
  } else if (call.method == 'onWatchVoiceFinished') {
    addDebugLog('Watch voice finished', 'Watch completed voice recognition');
  } else if (call.method == 'onWatchVoiceTimeout') {
    orangeWatchReassessmentAllowed = false;
    addDebugLog(
      'Watch heard no clear speech',
      'Watch heard no clear speech. Watch reassessment skipped due to low/calm context.',
    );
  } else if (call.method == 'onWatchVoiceError') {
    orangeWatchReassessmentAllowed = false;
    addDebugLog(
      'Watch voice error',
      '${call.arguments}. Watch reassessment skipped due to low/calm context.',
    );
  } else if (call.method == 'onNativeVoiceListening') {
    addDebugLog('Native mic listening', '${call.arguments}');
  } else if (call.method == 'onNativeVoiceError') {
    addDebugLog('Native voice error', '${call.arguments}');
  } else if (call.method == 'onNativeVoiceServiceStopped') {
    if (mounted) {
      setState(() {
        isListening = false;
        appStatus = _statusTextForStage();
      });
    }
  }
});

    initTts();
    initSpeech();
    startEngineLoop();
    startVoiceWindowLoop();
    
    addDebugLog(
      'Watch-only monitoring active',
      'CalmGuard initialized with watch as primary voice detection. Phone mic automatic fallback is fully paused.',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    evaluationTimer?.cancel();
    voiceWindowTimer?.cancel();
    evaluationDebounceTimer?.cancel();
    warningAutoCalmTimer?.cancel();
    orangeVoiceRecheckTimer?.cancel();
    voiceDebounceTimer?.cancel();
    speech.stop();
    flutterTts.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do not automatically kill monitoring when the phone locks or the app is paused.
    // This gives CalmGuard the best chance to keep receiving watch HR updates while testing.
    // Full production background reliability still needs Android foreground-service support.
    isAppInForeground = keepMonitoringWhenScreenLocked || state == AppLifecycleState.resumed;

    if (state == AppLifecycleState.resumed) {
      addDebugLog(
        'App foreground',
        'CalmGuard visible again. Monitoring continued where possible.',
      );
      pollPendingNativeVoiceResult();
      if (voiceWatchMode && !isSpeaking) {
        ensureVoiceWatchListening();
      }
    } else {
      addDebugLog(
        'App background/screen locked',
        'Keeping monitoring active where Android allows it. Native foreground service may still be required.',
      );
    }
  }


  void addDebugLog(String event, String details) {
    if (!mounted) return;

    final log = CalmGuardDebugLog(
      time: DateTime.now(),
      event: event,
      details: details,
    );

    setState(() {
      debugLogs.insert(0, log);
      if (debugLogs.length > 80) {
        debugLogs.removeRange(80, debugLogs.length);
      }
    });
  }

  String formatLogTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void cancelWarningAutoCalmTimer() {
    warningAutoCalmTimer?.cancel();
    warningAutoCalmTimer = null;
  }

  void cancelOrangeVoiceSampling() {
    orangeVoiceRecheckTimer?.cancel();
    orangeVoiceRecheckTimer = null;
    orangeVoiceChecksThisEvent = 0;
    orangeVoiceSamplingActive = false;
    orangeWatchReassessmentAllowed = false;
  }

  void unlockOrangeSession() {
    orangeSessionLocked = false;
    orangeVoiceChecksThisEvent = 0;
    orangeWatchReassessmentAllowed = false;
    addDebugLog('ORANGE session unlocked', 'ORANGE reassessment cycle complete. Ready for next ORANGE event if needed.');
  }

  void scheduleOrangeVoiceSampling({int delaySeconds = 2, String reason = 'ORANGE voice sampling'}) {
    if (stage != AlertStage.warning) return;
    // Native Android voice service now handles ORANGE sampling.
    // Do not block this just because Flutter speech_to_text is not active.
    if (orangeSessionLocked && orangeVoiceChecksThisEvent > 0) {
      addDebugLog(
        'ORANGE session locked',
        'Reassessment cycle already active. Wait for recovery to GREEN, RED escalation, or cooldown expiry.',
      );
      return;
    }

    if (orangeVoiceChecksThisEvent >= maxOrangeVoiceChecksPerEvent) {
      addDebugLog(
        'ORANGE voice sampling complete',
        'Maximum short checks reached for this ORANGE event.',
      );
      return;
    }

    if (orangeVoiceChecksThisEvent > 0 && !orangeWatchReassessmentAllowed) {
      addDebugLog(
        'ORANGE watch reassessment skipped',
        'Watch reassessment skipped due to low/calm context and not allowed for this ORANGE event.',
      );
      return;
    }

    orangeVoiceRecheckTimer?.cancel();
    orangeVoiceRecheckTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (!mounted) return;
      if (stage != AlertStage.warning) return;

      if (isSpeaking) {
        // Important: wait for CalmGuard's own voice prompt to finish so the mic
        // does not hear the app speaking and create false voice AI scores.
        scheduleOrangeVoiceSampling(delaySeconds: 1, reason: reason);
        return;
      }

      if (isListening) return;

      orangeVoiceChecksThisEvent++;
      orangeSessionLocked = true;
      orangeVoiceSamplingActive = true;
      allowVoiceCheck = true;
      voiceWatchMode = true;
      stopVoiceWatchRequested = false;
      orangeWatchReassessmentAllowed = false;

      addDebugLog(
        'ORANGE voice check ${orangeVoiceChecksThisEvent}/$maxOrangeVoiceChecksPerEvent',
        '$reason. Requesting watch voice first. Listening for $orangeVoiceWindowSeconds seconds.',
      );

      bool watchVoiceRequested = false;
      try {
        await voicePlatform.invokeMethod("requestWatchVoiceCheck");
        watchVoiceRequested = true;
        addDebugLog('Watch voice requested', 'Watch will start listening for ORANGE voice check');
      } catch (e) {
        addDebugLog(
          'Watch voice request failed',
          'Watch mic request failed. Phone mic fallback paused during ORANGE sampling.',
        );
        watchVoiceRequested = false;
      }

      if (!watchVoiceRequested) {
        voiceWatchMode = false;
        allowVoiceCheck = false;
        addDebugLog(
          'Automatic phone mic paused',
          'Watch mic request failed. Automatic phone mic fallback is fully paused. Watch is primary voice detection during ORANGE.',
        );
      }

      // If the situation is still ORANGE later, run another short check.
      // This is not always-listening. It is limited reassessment during active warning.
      Future.delayed(
        const Duration(seconds: orangeVoiceWindowSeconds + orangeVoiceRecheckDelaySeconds),
        () {
          if (!mounted) return;
          orangeVoiceSamplingActive = false;
          if (stage == AlertStage.warning &&
              orangeVoiceChecksThisEvent < maxOrangeVoiceChecksPerEvent) {
            scheduleOrangeVoiceSampling(
              delaySeconds: 0,
              reason: 'ORANGE still active, running another short reassessment',
            );
          }
        },
      );
    });
  }


  void scheduleManualWarningAutoCalm() {
    cancelWarningAutoCalmTimer();

    // This is only for the Simulate Warning button.
    // It creates a realistic temporary spike, then lets signals settle.
    warningAutoCalmTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (stage != AlertStage.warning) return;

      setState(() {
        watchHeartRate = 72;
        stressLevel = 20;
        smoothedWatchStress = 20.0;
        voiceLevel = 8.0;
        voiceAiScore = 0.0;
        voiceSpikesLastMinute = 0;
        voiceBehaviourStatus = 'Voice calm';
        voiceContextScore = 0.0;
        voiceContextStatus = 'No concerning words detected';
        lastVoiceContextTime = null;
        manualWarningTestActive = false;
        manualWarningTestUntil = null;
        triggerReason = 'Warning signals are settling. Watching for recovery.';
      });

      addDebugLog(
        'Manual warning settled',
        'Signals returned to calm values. Warning memory was kept.',
      );

      scheduleEvaluation();
    });
  }

  void updatePatternStatusFromEngine() {
    final warningCount5m = engine.lastMetrics?.warningCountIn5Min ?? 0;
    warningPatternScore = warningCount5m.clamp(0, 5);

    if (warningCount5m >= 3) {
      patternStatus = 'Escalation pattern detected';
    } else if (warningCount5m > 0) {
      patternStatus = 'Warnings in last 5 min: $warningCount5m';
    } else {
      patternStatus = 'No escalation pattern';
    }
  }

  void resetLocalState({
    required bool resetEngineToo,
    required bool resetSignals,
  }) {
    if (resetEngineToo) {
      engine.resetEngine();
    }

    stage = AlertStage.monitoring;
    warning = false;
    triggered = false;
    isSpeaking = false;
    isListening = false;
    voiceWatchMode = false;
    stopVoiceWatchRequested = true;
    allowVoiceCheck = false;

    appStatus = 'Monitoring';
    triggerReason = 'All signals normal';
    heardText = 'No voice sample yet';
    patternStatus = 'No escalation pattern';

    liveStressScore = 20.0;
    aiStressLevel = 20;
    warningPatternScore = 0;
    voiceAiScore = 0.0;
    voiceSpikesLastMinute = 0;
    voiceBehaviourStatus = 'Voice calm';
    voiceContextScore = 0.0;
    voiceContextStatus = 'No concerning words detected';
    lastVoiceContextTime = null;
    lastProcessedVoiceText = '';
    lastProcessedVoiceTextTime = null;
    lastConversationRiskCategory = 'calm';
    voiceConfidenceScore = 0.0;
    pendingVoiceText = '';
    voiceDebounceTimer?.cancel();
    lastNativePendingPullTime = null;
    lastAutoVoiceCheckTime = null;
    smartVoiceSessionActive = false;
    smartVoiceSessionEndTime = null;
    voiceEngine.reset();
    lastWarningTime = null;
    lastTriggerTime = null;
    uiWarningHoldStart = null;
    orangeVoiceChecksThisEvent = 0;
    orangeVoiceSamplingActive = false;
    redRecoveryMessagePlayed = false;
    deepOrangeActive = false;
    deepOrangeStart = null;

    if (resetSignals) {
      watchHeartRate = 72;
      stressLevel = 20;
      smoothedWatchStress = 20.0;
      voiceLevel = 8.0;
    }
  }

void applyVoiceDecay() {
  // ❌ Do NOT decay during active situations
  if (stage == AlertStage.triggered) return;
  if (cooldownActive) return;
  if (isListening || isSpeaking) return;

  final learnedHrBaseline =
      personalHrBaselineSamples < 10 ? 72.0 : personalHrBaseline;

  final hrDiff = (watchHeartRate - learnedHrBaseline).abs();

  final noRecentConcern = lastVoiceContextTime == null ||
      DateTime.now().difference(lastVoiceContextTime!).inSeconds > 25;

  // ✅ Only decay when calm conditions
  if (hrDiff <= 8 && noRecentConcern) {
    bool didResetToCalm = false;
    setState(() {
      voiceAiScore = (voiceAiScore - 4).clamp(0.0, 100.0);
      voiceLevel = (voiceLevel - 2).clamp(0.0, 100.0);
      voiceContextScore = (voiceContextScore - 3).clamp(0.0, 100.0);

      // Reset when almost calm
      if (voiceAiScore <= 8) {
        voiceAiScore = 0.0;
        voiceSpikesLastMinute = 0;
        voiceBehaviourStatus = 'Voice calm';
        voiceContextScore = 0.0;
        voiceContextStatus = 'No concerning words detected';
        lastVoiceContextTime = null;
        lastProcessedVoiceText = '';
        lastProcessedVoiceTextTime = null;
        lastConversationRiskCategory = 'calm';
        voiceConfidenceScore = 0.0;
        didResetToCalm = true;
      }
    });

    // Throttle decay debug logs to at most once every 20 seconds
    if (didResetToCalm) {
      final now = DateTime.now();
      if (lastVoiceDecayLogTime == null || now.difference(lastVoiceDecayLogTime!).inSeconds >= 20) {
        addDebugLog('Voice/context decay applied', 'Aggressive voice context gradually reduced due to calm conditions.');
        lastVoiceDecayLogTime = now;
      }
    }
  }
}

  Future<void> initTts() async {
    await flutterTts.setLanguage('en-AU');
    await flutterTts.setSpeechRate(0.45);
    await flutterTts.setPitch(1.0);

    flutterTts.setStartHandler(() {
      if (!mounted) return;
      setState(() => isSpeaking = true);
    });

    flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => isSpeaking = false);
      if (stage == AlertStage.warning) {
        scheduleOrangeVoiceSampling(
          delaySeconds: 0,
          reason: 'Warning prompt finished, starting ORANGE voice sample',
        );
      } else if (voiceWatchMode) {
        ensureVoiceWatchListening();
      }
    });

    flutterTts.setCancelHandler(() {
      if (!mounted) return;
      setState(() => isSpeaking = false);
      if (stage == AlertStage.warning) {
        scheduleOrangeVoiceSampling(
          delaySeconds: 0,
          reason: 'Warning prompt finished, starting ORANGE voice sample',
        );
      } else if (voiceWatchMode) {
        ensureVoiceWatchListening();
      }
    });

    flutterTts.setErrorHandler((message) {
      if (!mounted) return;
      setState(() => isSpeaking = false);
      if (stage == AlertStage.warning) {
        scheduleOrangeVoiceSampling(
          delaySeconds: 0,
          reason: 'Warning prompt finished, starting ORANGE voice sample',
        );
      } else if (voiceWatchMode) {
        ensureVoiceWatchListening();
      }
    });

    ttsReady = true;
  }

  Future<void> initSpeech() async {
    speechEnabled = await speech.initialize(
      onStatus: (status) {
        if (!mounted) return;

        if (status == 'done' || status == 'notListening') {
          setState(() {
            isListening = false;
            appStatus = _statusTextForStage();
          });

          if (stage == AlertStage.triggered) {
            _stopSmartVoiceSession();
            return;
          }

          if (orangeVoiceSamplingActive) {
            orangeVoiceSamplingActive = false;
            addDebugLog(
              'ORANGE voice check finished',
              'Mic closed after short ORANGE sample. Waiting before any reassessment.',
            );
          }

          // Do not auto-reopen the mic immediately. ORANGE reassessments are controlled
          // by scheduleOrangeVoiceSampling so it does not feel like a mic loop.
          if (stage == AlertStage.warning &&
              orangeVoiceChecksThisEvent < maxOrangeVoiceChecksPerEvent) {
            scheduleOrangeVoiceSampling(
              delaySeconds: orangeVoiceRecheckDelaySeconds,
              reason: 'ORANGE still active after previous voice sample',
            );
          }
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          isListening = false;
          heardText = 'Voice check error: ${error.errorMsg}';
          appStatus = _statusTextForStage();
        });

        if (stage == AlertStage.triggered) {
          _stopSmartVoiceSession();
          return;
        }

        // Do not auto-reopen after errors. Keep the app calm and predictable.
      },
    );

    if (mounted) setState(() {});
  }

  String _statusTextForStage() {
    if (stage == AlertStage.warning) return 'Warning';
    if (stage == AlertStage.triggered) return 'Triggered';
    return 'Monitoring';
  }


  Future<void> pollPendingNativeVoiceResult() async {
    if (!nativePendingPullSupported) return;

    final now = DateTime.now();
    if (lastNativePendingPullTime != null &&
        now.difference(lastNativePendingPullTime!).inSeconds < 3) {
      return;
    }

    lastNativePendingPullTime = now;

    try {
      final result = await voicePlatform.invokeMethod('getPendingVoiceResult');

      if (result is Map) {
        final text = (result['text'] ?? '').toString().trim();
        final timestamp = result['timestamp'];

        if (text.isNotEmpty) {
          addDebugLog(
            'Native pending voice pulled',
            '"$text" from background buffer. Timestamp: $timestamp',
          );
          processVoiceText(text);
        }
      }
    } catch (_) {
      // Older native code may not have getPendingVoiceResult yet.
      // Disable polling silently so logs do not get spammed.
      nativePendingPullSupported = false;
    }
  }

  void startEngineLoop() {
    evaluationTimer?.cancel();
    evaluationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      pollPendingNativeVoiceResult();
      evaluateSmartState();
      applyVoiceDecay();
    });
  }

  void scheduleEvaluation() {
    evaluationDebounceTimer?.cancel();
    // Do NOT cancel warningAutoCalmTimer here.
    // That timer is what lets Simulate Warning settle back to calm values.
    evaluationDebounceTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) evaluateSmartState();
    });
  }

  void startVoiceWindowLoop() {
    voiceWindowTimer?.cancel();

    voiceWindowTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!autoVoiceWindowsEnabled) return;
      if (!allowVoiceCheck && stage == AlertStage.monitoring) return;
      if (isListening) return;
      if (isSpeaking) return;
      if (!isAppInForeground) return;

      if (stage == AlertStage.triggered) return;

      if (stage == AlertStage.warning) {
        scheduleOrangeVoiceSampling(delaySeconds: 0, reason: 'Scheduled ORANGE voice reassessment');
      } else {
        startTemporaryListeningWindow(seconds: 20, reason: 'Scheduled voice check');
      }
    });
  }

  Future<void> startTemporaryListeningWindow({
  int seconds = 20,
  String reason = 'Voice check',
  bool isManual = false,
}) async {
  if (phoneMicAutoDisabled && !isManual) {
    addDebugLog(
      'Automatic phone mic blocked',
      'Automatic phone mic activation is disabled. Manual microphone tests can still be run explicitly.',
    );
    return;
  }

  if (isListening || isSpeaking) return;
  if (stage == AlertStage.triggered) return;

  smartVoiceSessionActive = true;
  smartVoiceSessionEndTime =
      DateTime.now().add(Duration(seconds: seconds));

  setState(() {
    isListening = true;
    appStatus = 'Checking voice';
    heardText = 'Native voice check active...';
  });

  addDebugLog(
    reason,
    'Native mic service requested for $seconds seconds. CalmGuard does not play mic start/end prompts.',
  );

  try {
    await speech.listen(
      listenFor: Duration(seconds: seconds),
      pauseFor: const Duration(seconds: 6),
      partialResults: true,
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        if (!mounted) return;

        final text = result.recognizedWords.trim();

        if (text.isNotEmpty) {
          setState(() => heardText = text);
          processVoiceText(text);
        }
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;

        final normalized =
            ((level + 2).clamp(0, 45) / 45.0) * 100.0;

        processVoiceLevel(
          normalized.clamp(0, 100).toDouble(),
        );
      },
    );
  } catch (e) {
    addDebugLog('Voice start failed', e.toString());

    if (mounted) {
      setState(() => isListening = false);
    }
  }
}
  bool _shouldContinueSmartVoiceSession() {
    if (!smartVoiceSessionActive) return false;
    if (smartVoiceSessionEndTime == null) return false;
    if (!isAppInForeground || isSpeaking) return false;
    return DateTime.now().isBefore(smartVoiceSessionEndTime!);
  }

  int _remainingSmartVoiceSeconds() {
    if (smartVoiceSessionEndTime == null) return 0;
    return smartVoiceSessionEndTime!.difference(DateTime.now()).inSeconds;
  }

  void _continueSmartVoiceSession() {
    if (!_shouldContinueSmartVoiceSession()) {
      _stopSmartVoiceSession();
      return;
    }
  }

  void _stopSmartVoiceSession() {
    smartVoiceSessionActive = false;
    smartVoiceSessionEndTime = null;
  }

  double normalizeVoiceLevel(double rawLevel) {
    final shifted = (rawLevel + 2).clamp(0, 45);
    final normalized = (shifted / 45.0) * 100.0;
    return normalized.clamp(0, 100).toDouble();
  }

  Future<void> speakMessage(String message) async {
    if (!ttsReady) return;
    if (!isAppInForeground) return;
    if (message.trim().isEmpty) return;
    if (isSpeaking) return;

    if (isListening) {
      await speech.stop();
      if (mounted) setState(() => isListening = false);
    }

    await flutterTts.stop();
    await flutterTts.speak(message);
  }

  Future<void> ensureVoiceWatchListening() async {
    if (phoneMicAutoDisabled) {
      addDebugLog(
        'Automatic phone mic blocked',
        'Phone mic is disabled for automatic watch listening sessions.',
      );
      return;
    }
    if (stopVoiceWatchRequested) return;
    if (!voiceWatchMode) return;
    if (!allowVoiceCheck) return;
    if (!speechEnabled) return;
    if (isSpeaking) return;
    if (isListening) return;
    if (!isAppInForeground) return;

    setState(() {
      isListening = true;
      appStatus = 'Checking voice';
    });

    await speech.listen(
      listenFor: const Duration(seconds: 25),
      pauseFor: const Duration(seconds: 6),
      partialResults: true,
      cancelOnError: false,
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        if (!mounted) return;
        final text = result.recognizedWords.trim();
        if (text.isNotEmpty) {
          setState(() => heardText = text);
          processVoiceText(text);
        }
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
       final normalized = ((level + 2).clamp(0, 45) / 45.0) * 100.0;
        processVoiceLevel(normalized.clamp(0, 100).toDouble());
      },
    );
  }

  Future<void> stopVoiceListeningHard() async {
    stopVoiceWatchRequested = true;
    voiceWatchMode = false;
    allowVoiceCheck = false;

    if (isListening) {
      await speech.stop();
    }

    try {
      await voicePlatform.invokeMethod('stopVoiceService');
    } catch (_) {
      // Native service may not be running. Safe to ignore.
    }

    if (mounted) {
      setState(() => isListening = false);
    }
  }

  Future<void> vibrateWarning() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 300);
    }
  }

  Future<void> vibrateTrigger() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 300, 120, 300, 120, 500]);
    }
  }

  void calculateLiveStress() {
    final learnedHrBaseline =
        personalHrBaselineSamples < 10 ? 72.0 : personalHrBaseline;

    final hrAboveBaseline = (watchHeartRate - learnedHrBaseline).clamp(0.0, 120.0);
    final hrPart = (hrAboveBaseline / 45.0).clamp(0.0, 1.0);
    final watchStressPart = (stressLevel / 100.0).clamp(0.0, 1.0);
    final voicePart = (voiceAiScore / 100.0).clamp(0.0, 1.0);
    final patternPart = (warningPatternScore / 5.0).clamp(0.0, 1.0);

    // AI Stress v2:
    // HR alone is treated carefully because exercise/walking can raise HR.
    // Voice AI + stress confirmation makes the system much more reliable.
    final multiSignalBonus =
        ((hrPart >= 0.45 && watchStressPart >= 0.45) ||
                (hrPart >= 0.45 && voicePart >= 0.45) ||
                (watchStressPart >= 0.45 && voicePart >= 0.45))
            ? 0.10
            : 0.0;

    final exerciseFilterPenalty =
        (hrPart >= 0.55 && watchStressPart < 0.35 && voicePart < 0.30)
            ? 0.18
            : 0.0;

    final combined =
        (hrPart * 0.26) +
        (watchStressPart * 0.32) +
        (voicePart * 0.32) +
        (patternPart * 0.10) +
        multiSignalBonus -
        exerciseFilterPenalty;

    liveStressScore = (combined * 100.0).clamp(0.0, 100.0);
    aiStressLevel = liveStressScore.round().clamp(0, 100);
  }

  void evaluateSmartState() {
    if (cooldownActive) {
  if (cooldownEndTime != null &&
      DateTime.now().isAfter(cooldownEndTime!)) {
    cooldownActive = false;
    cooldownEndTime = null;

    recoveryActive = true;
    recoveryEndTime = DateTime.now().add(const Duration(seconds: 20));

    setState(() {
      stage = AlertStage.monitoring;
      warning = false;
      triggered = false;
      appStatus = 'Recovering...';
      triggerReason = 'Cooldown complete. Signals reset to calm for recovery.';
      watchHeartRate = 72;
      stressLevel = 20;
      smoothedWatchStress = 20.0;
      voiceLevel = 8.0;
      voiceAiScore = 0.0;
      voiceSpikesLastMinute = 0;
      voiceBehaviourStatus = 'Voice calm';
      voiceContextScore = 0.0;
      voiceContextStatus = 'No concerning words detected';
      lastVoiceContextTime = null;
      voiceWatchMode = false;
      allowVoiceCheck = false;
      stopVoiceWatchRequested = true;
    });
    return;
  }
}

if (recoveryActive) {
  applyVoiceDecay();

  if (recoveryEndTime != null &&
      DateTime.now().isAfter(recoveryEndTime!)) {
    recoveryActive = false;
    recoveryEndTime = null;

    setState(() {
      appStatus = 'Monitoring';
      triggerReason = 'Recovery complete. Back in calm monitoring mode.';
    });

    addDebugLog(
      'RED recovery complete',
      'Cooldown and recovery finished. CalmGuard returned to GREEN monitoring.',
    );

    if (!redRecoveryMessagePlayed) {
      redRecoveryMessagePlayed = true;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        if (!isSpeaking && stage == AlertStage.monitoring) {
          speakMessage('You are back in calm monitoring mode.');
        }
      });
    }
    return;
  }
}
  calculateLiveStress();

    final decision = engine.evaluate(
      heartRate: watchHeartRate.toDouble(),
      stress: aiStressLevel.toDouble(),
      voice: voiceAiScore,
      now: DateTime.now(),
      currentStage: stage,
    );

    if (!mounted) return;

    final now = DateTime.now();
    final warningCount5m = engine.lastMetrics?.warningCountIn5Min ?? 0;
    final warningHeldSeconds = stage == AlertStage.warning && uiWarningHoldStart != null
        ? now.difference(uiWarningHoldStart!).inSeconds
        : 0;
    final currentRiskScore = engine.lastMetrics?.score ?? 0.0;
    final sustainedVeryHighWarning = warningHeldSeconds >= 18 && currentRiskScore >= 0.92;

    if (stage == AlertStage.warning) {
      if (!deepOrangeActive && warningHeldSeconds >= 10) {
        final hrElevated = watchHeartRate >= engine.hrBaseline + 15;
        final stressElevated = aiStressLevel >= engine.stressBaseline + 15;
        final voiceElevated = voiceAiScore >= engine.voiceBaseline + 15;
        final strongVoiceContext = voiceAiScore >= 70 || voiceContextScore >= 70;
        final elevatedSignals = <bool>[hrElevated, stressElevated, voiceElevated]
            .where((value) => value)
            .length;

        if (elevatedSignals >= 2 || (strongVoiceContext && hrElevated)) {
          deepOrangeActive = true;
          deepOrangeStart = now;
          addDebugLog(
            'DEEP ORANGE entered',
            'ORANGE persisted for $warningHeldSeconds seconds with sufficient signal quality. HR ${hrElevated ? 'elevated' : 'calm'}, risk ${stressElevated ? 'elevated' : 'calm'}, voice ${voiceElevated ? 'elevated' : 'calm'}, context ${strongVoiceContext ? 'strong' : 'weak'}.',
          );
        } else {
          addDebugLog(
            'DEEP ORANGE deferred',
            'ORANGE persisted for $warningHeldSeconds seconds but signal quality is not strong enough yet. Elevated signals: $elevatedSignals, strong voice/context: $strongVoiceContext.',
          );
        }
      }
    } else if (deepOrangeActive) {
      deepOrangeActive = false;
      deepOrangeStart = null;
      addDebugLog(
        'DEEP ORANGE cleared',
        'Internal escalation layer cleared because ORANGE ended.',
      );
    }

    updatePatternStatusFromEngine();

    if (decision.action == EngineAction.warning &&
        stage == AlertStage.monitoring) {
      setState(() {
        stage = AlertStage.warning;
        warning = true;
        triggered = false;
        voiceWatchMode = true;
        allowVoiceCheck = true;
        stopVoiceWatchRequested = false;
        orangeVoiceChecksThisEvent = 0;
        orangeSessionLocked = false;
        orangeVoiceSamplingActive = false;
        orangeWatchReassessmentAllowed = true;
        appStatus = 'Warning';
        triggerReason = decision.reason;
        lastWarningTime = DateTime.now();
        uiWarningHoldStart = DateTime.now();
        deepOrangeActive = false;
        deepOrangeStart = null;
      });

      addDebugLog(
        'ORANGE warning',
        '${decision.reason} | HR $watchHeartRate | risk $aiStressLevel | voice ${voiceAiScore.toStringAsFixed(0)} | warnings/5m $warningCount5m',
      );

      speakMessage(
        'Warning. I can sense rising pressure. Take a breath and slow down.',
      );
      vibrateWarning();

      // After the warning prompt finishes, open a quiet 20-second voice sample.
      // This follows the core CalmGuard rule: selective voice sampling only during elevated risk.
      scheduleOrangeVoiceSampling(
        delaySeconds: 2,
        reason: 'ORANGE started from elevated signals',
      );
      return;
    }

    if (decision.action == EngineAction.trigger &&
        stage != AlertStage.triggered) {
      final manualWarningStillProtected = manualWarningTestActive &&
          manualWarningTestUntil != null &&
          DateTime.now().isBefore(manualWarningTestUntil!);

      if (manualWarningStillProtected) {
        addDebugLog(
          'Trigger blocked during warning test',
          'Simulate Warning is protected so ORANGE recovery can be tested without jumping to RED.',
        );
        return;
      }

      if (stage == AlertStage.warning && !deepOrangeActive && !sustainedVeryHighWarning) {
        addDebugLog(
          'RED deferred until deep escalation persistence',
          'Trigger deferred because ORANGE has not yet reached internal DEEP ORANGE or very high sustained risk.',
        );
        return;
      }

      cancelWarningAutoCalmTimer();
      cancelOrangeVoiceSampling();
      unlockOrangeSession();
      redRecoveryMessagePlayed = false;
      cooldownActive = true;
      cooldownEndTime = DateTime.now().add(const Duration(seconds: 45));    

      setState(() {
        stage = AlertStage.triggered;
        warning = false;
        triggered = true;
        voiceWatchMode = false;
        allowVoiceCheck = false;
        stopVoiceWatchRequested = true;
        appStatus = 'Triggered';
        triggerReason = decision.reason;
        lastTriggerTime = DateTime.now();
      });

      addDebugLog(
        'RED trigger',
        '${decision.reason} | HR $watchHeartRate | risk $aiStressLevel | voice ${voiceAiScore.toStringAsFixed(0)}',
      );

      speakMessage('Calm down. Take a breath. You are in control.');
      vibrateTrigger();
      return;
    }

    if (decision.action == EngineAction.reset) {
      if (stage == AlertStage.warning && uiWarningHoldStart != null) {
        final heldSeconds =
            DateTime.now().difference(uiWarningHoldStart!).inSeconds;
        if (heldSeconds < 5) return;
      }

      setState(() {
        stage = AlertStage.monitoring;
        warning = false;
        triggered = false;
        orangeVoiceChecksThisEvent = 0;
        orangeSessionLocked = false;
        orangeVoiceSamplingActive = false;
        voiceWatchMode = false;
        stopVoiceWatchRequested = true;
        allowVoiceCheck = false;
        appStatus = 'Monitoring';
        triggerReason = decision.reason;
        uiWarningHoldStart = null;
      manualWarningTestActive = false;
      manualWarningTestUntil = null;
      });

      stopVoiceListeningHard();
      unlockOrangeSession();
      addDebugLog(
        'Auto recovery to GREEN',
        '${decision.reason}. Warnings/5m kept at ${engine.lastMetrics?.warningCountIn5Min ?? 0}. Watch-only monitoring now active.',
      );

      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        if (!isSpeaking && stage == AlertStage.monitoring) {
          speakMessage('Good job, you are back in calm mode.');
        }
      });
      return;
    }

    setState(() {
      triggerReason = decision.reason;
      appStatus = isListening ? 'Checking voice' : _statusTextForStage();
    });
  }

  void updateHeartRateFromWatch(int value) {
    final now = DateTime.now();

    // Real watches can send too many readings. This prevents UI overload.
    if (lastHeartRateUpdate != null &&
        now.difference(lastHeartRateUpdate!).inMilliseconds < 900) {
      return;
    }

    final cleanValue = value.clamp(40, 220);

    setState(() {
      watchHeartRate = cleanValue;
      lastHeartRateUpdate = now;
    });

    // Learn personal HR baseline only while calm.
    if (stage == AlertStage.monitoring &&
        stressLevel < 35 &&
        cleanValue >= 45 &&
        cleanValue <= 115) {
      personalHrBaseline =
          ((personalHrBaseline * personalHrBaselineSamples) + cleanValue) /
              (personalHrBaselineSamples + 1);
      personalHrBaselineSamples++;
    }

    scheduleEvaluation();
    maybeOpenVoiceCheckFromHeartRate();
  }

  void updateStressFromWatch(int value) {
    final cleanValue = value.clamp(0, 100).toDouble();
    smoothedWatchStress = (smoothedWatchStress * 0.75) + (cleanValue * 0.25);

    setState(() {
      stressLevel = smoothedWatchStress.round().clamp(0, 100);
    });

    scheduleEvaluation();
  }

  void processVoiceLevel(double value) {
    final cleanValue = value.clamp(0, 100).toDouble();
    final decision = voiceEngine.evaluate(
      level: cleanValue,
      now: DateTime.now(),
    );

    final fadedContextScore = _currentVoiceContextScore();
    final combinedVoiceScore = math.max(decision.score, fadedContextScore);

    setState(() {
      voiceLevel = cleanValue;
      voiceAiScore = combinedVoiceScore;
      voiceSpikesLastMinute = decision.spikesLastMinute;
      voiceBehaviourStatus = decision.score >= fadedContextScore
          ? decision.reason
          : voiceContextStatus;
    });

    scheduleEvaluation();
  }

  void processVoiceText(String text) {
  final cleanText = text.toLowerCase().trim();

  if (cleanText.isEmpty) return;

  // Debounce first so Android partial speech results settle
  pendingVoiceText = cleanText;

  voiceDebounceTimer?.cancel();

  voiceDebounceTimer = Timer(const Duration(milliseconds: 900), () {
    if (!mounted) return;

    final finalText = pendingVoiceText.trim();

    // Ignore CalmGuard's own TTS only AFTER debounce
    if (_isCalmGuardOwnSpeech(finalText)) {
      addDebugLog(
        'Self voice ignored',
        '"$finalText" matches CalmGuard TTS/self-speech suppression.',
      );
      return;
    }

    _processFinalVoiceText(finalText);
  });
}

  void _processFinalVoiceText(String cleanText) {
    if (cleanText.isEmpty) return;

    final now = DateTime.now();

    // Ignore exact duplicate phrases for a short time so one sentence does not
    // artificially stack into RED because of repeated native partial/final callbacks.
    if (cleanText == lastProcessedVoiceText &&
        lastProcessedVoiceTextTime != null &&
        now.difference(lastProcessedVoiceTextTime!).inSeconds < 8) {
      addDebugLog(
        'Voice duplicate ignored',
        '"$cleanText" was already processed recently.',
      );
      return;
    }

    final risk = classifyConversationRisk(cleanText);

    // Still remember calm/neutral text briefly so repeated calm partials do not spam.
    if (risk.score <= 0) {
      lastProcessedVoiceText = cleanText;
      lastProcessedVoiceTextTime = now;
      lastConversationRiskCategory = risk.category;
      voiceConfidenceScore = 0.0;
      if (mounted) {
        setState(() {
          heardText = cleanText;
          voiceContextStatus = risk.label;
        });
      }
      return;
    }

    final learnedHrBaseline =
        personalHrBaselineSamples < 10 ? 72.0 : personalHrBaseline;

    final hrElevated = watchHeartRate >= learnedHrBaseline + 15;
    final riskElevated = aiStressLevel >= 45;
    final inWarning = stage == AlertStage.warning;

    final isMild = risk.category == 'mild_frustration' ||
        risk.category == 'frustration' ||
        risk.category == 'tension';

    final isBoundary = risk.category == 'boundary' ||
        risk.category == 'argument' ||
        risk.category == 'repetition';

    final isSerious = risk.category == 'aggressive' ||
        risk.category == 'repeated_stop' ||
        risk.category == 'escalation' ||
        risk.category == 'urgent';

    double adjustedScore = risk.score;

    // Context weighting:
    // Mild frustration should strengthen ORANGE, but should not instantly RED.
    // Serious/boundary language gets more weight when body signals are also elevated.
    if (hrElevated) adjustedScore += isMild ? 4 : 8;
    if (riskElevated) adjustedScore += isMild ? 2 : 8;
    if (inWarning) adjustedScore += isMild ? 0 : 6;

    if (isBoundary && hrElevated) adjustedScore += 4;
    if (isSerious && hrElevated && riskElevated) adjustedScore += 6;

    // False-positive control caps.
    if (isMild) {
      adjustedScore = adjustedScore.clamp(0.0, 48.0);
    } else if (isBoundary) {
      adjustedScore = adjustedScore.clamp(0.0, 72.0);
    } else if (risk.category == 'aggressive') {
      adjustedScore = adjustedScore.clamp(0.0, 82.0);
    } else if (risk.category == 'repeated_stop') {
      adjustedScore = adjustedScore.clamp(0.0, 84.0);
    } else if (risk.category == 'urgent') {
      adjustedScore = adjustedScore.clamp(0.0, 95.0);
    } else {
      adjustedScore = adjustedScore.clamp(0.0, 100.0);
    }

    final wordCount = cleanText
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .length;

    double confidence = 45.0;
    if (wordCount >= 3) confidence += 15;
    if (wordCount >= 6) confidence += 10;
    if (hrElevated) confidence += 10;
    if (riskElevated) confidence += 10;
    if (inWarning) confidence += 5;
    if (isSerious) confidence += 10;
    confidence = confidence.clamp(0.0, 100.0);

    setState(() {
      voiceContextScore = adjustedScore;
      lastVoiceContextTime = now;
      lastProcessedVoiceText = cleanText;
      lastProcessedVoiceTextTime = now;
      lastConversationRiskCategory = risk.category;
      voiceConfidenceScore = confidence;
      voiceContextStatus = risk.label;
      voiceAiScore = math.max(voiceAiScore, adjustedScore);
      voiceBehaviourStatus =
          '${risk.label} • ${adjustedScore.toStringAsFixed(0)}/100 • confidence ${confidence.toStringAsFixed(0)}%';
      heardText = cleanText;
    });

    addDebugLog(
      'Voice meaning detected',
      '"$cleanText" → ${risk.label}. Score ${adjustedScore.toStringAsFixed(0)} | confidence ${confidence.toStringAsFixed(0)}% | category ${risk.category}',
    );

    _updateOrangeWatchReassessmentFromVoiceResult();
    scheduleEvaluation();
  }

  void _updateOrangeWatchReassessmentFromVoiceResult() {
    if (!voiceWatchMode || stage != AlertStage.warning) return;

    final strongWatchContext =
        voiceContextScore >= 70 || voiceConfidenceScore >= 70;
    orangeWatchReassessmentAllowed = strongWatchContext;

    addDebugLog(
      strongWatchContext
          ? 'Watch reassessment allowed due to strong voice context'
          : 'Watch reassessment skipped due to low/calm context',
      strongWatchContext
          ? 'Watch result had strong voice context and one more ORANGE watch reassessment is permitted.'
          : 'Watch result was calm or low confidence. Do not reopen watch mic repeatedly for this ORANGE event.',
    );
  }

  ConversationRisk classifyConversationRisk(String text) {
    final calmPhrases = <String>[
      'i am testing',
      "i'm testing",
      'just testing',
      'testing the app',
      'i am okay',
      "i'm okay",
      'all good',
      'nothing wrong',
      'normal test',
    ];

    for (final phrase in calmPhrases) {
      if (text.contains(phrase)) {
        return const ConversationRisk(
          score: 0,
          label: 'Normal conversation detected',
          category: 'calm',
        );
      }
    }

  final mildStressPhrases = <String>[
   'i am getting frustrated',
   "i'm getting frustrated",
   'please stop',
   'stop please',
   'i already told you',
   'listen to me',
   'why are you doing this',
   'this is annoying',
   'can you stop',
   'enough already',
];

for (final phrase in mildStressPhrases) {
  if (text.contains(phrase)) {
    return const ConversationRisk(
      score: 35,
      label: 'Mild frustration detected',
      category: 'mild_frustration',
    );
  }
}

final aggressivePhrases = <String>[
  'leave me alone',
  'get away from me',
  'i am angry',
  "i'm angry",
  'dont touch me',
  "don't touch me",
  'go away',
  'i hate this',
  'shut up',
  'stop talking',
  'i cant take this',
  "i can't take this",
  'back off',
];

for (final phrase in aggressivePhrases) {
  if (text.contains(phrase)) {
    return const ConversationRisk(
      score: 75,
      label: 'Aggressive conversation detected',
      category: 'aggressive',
    );
  }
}

 final stopCount = RegExp(r'\bstop\b').allMatches(text).length;

if (stopCount >= 2) {
  return const ConversationRisk(
    score: 75,
    label: 'Repeated STOP escalation',
    category: 'repeated_stop',
  );
}

    final urgentSafety = <String>[
      'do not touch me',
      "don't touch me",
      'get away from me',
      'leave me alone',
      'move away from me',
      'back off now',
      'i feel unsafe',
      'help me',
    ];

    final escalation = <String>[
      'shut up',
      'stop it right now',
      'i said stop',
      'i told you already',
      'enough is enough',
      'i am angry',
      "i'm angry",
      'pissed off',
      'fed up',
      'get away',
    ];

    final boundary = <String>[
      'stop it',
      'stop talking',
      'back off',
      'move away',
      'leave it',
      'give me space',
      'do not talk to me',
      "don't talk to me",
    ];

    final argument = <String>[
      'you never',
      'you always',
      'listen to me',
      'why are you',
      'why do you',
      'what is wrong with you',
      'not fair',
      'seriously',
      'you do this every time',
    ];

    final frustration = <String>[
      'i am frustrated',
      "i'm frustrated",
      'this is annoying',
      'i cannot deal with this',
      "i can't deal with this",
      'i am sick of this',
      "i'm sick of this",
      'this is too much',
    ];

    int urgentHits = _countPhraseHits(text, urgentSafety);
    int escalationHits = _countPhraseHits(text, escalation);
    int boundaryHits = _countPhraseHits(text, boundary);
    int argumentHits = _countPhraseHits(text, argument);
    int frustrationHits = _countPhraseHits(text, frustration);
    final repeatedWords = _hasRepeatedWords(text);
    final intensityHits = _countIntensityWords(text);
    final directYouBlame = _hasYouBlamePattern(text);

    double score = 0.0;
    String label = 'Normal conversation detected';
    String category = 'calm';

    if (urgentHits > 0) {
      score = 82 + (urgentHits * 8) + (intensityHits * 4);
      label = 'Urgent safety language detected';
      category = 'urgent';
    } else if (escalationHits > 0) {
      score = 68 + (escalationHits * 8) + (boundaryHits * 4) + (intensityHits * 4);
      label = 'Escalating conversation detected';
      category = 'escalation';
    } else if (boundaryHits > 0 && argumentHits > 0) {
      score = 62 + (boundaryHits * 6) + (argumentHits * 5) + (intensityHits * 4);
      label = 'Argument with boundary language detected';
      category = 'argument';
    } else if (boundaryHits > 0) {
      score = 56 + (boundaryHits * 7) + (intensityHits * 4);
      label = 'Boundary phrase detected';
      category = 'boundary';
    } else if (argumentHits >= 2 || directYouBlame) {
      score = 48 + (argumentHits * 7) + (intensityHits * 4);
      label = 'Argument-style wording detected';
      category = 'argument';
    } else if (argumentHits == 1) {
      score = 36 + (intensityHits * 4);
      label = 'Tension building in conversation';
      category = 'tension';
    } else if (frustrationHits > 0) {
      score = 34 + (frustrationHits * 7) + (intensityHits * 4);
      label = 'Frustration language detected';
      category = 'frustration';
    } else if (repeatedWords) {
      score = 30 + (intensityHits * 4);
      label = 'Repeated wording detected';
      category = 'repetition';
    }

    if (repeatedWords && score > 0) score += 8;
    if (text.endsWith('!')) score += 4;
    if (text.split(' ').length <= 3 && score < 60) score *= 0.75;

    score = score.clamp(0.0, 100.0);

    return ConversationRisk(
      score: score,
      label: label,
      category: category,
    );
  }

  int _countPhraseHits(String text, List<String> phrases) {
    int count = 0;
    for (final phrase in phrases) {
      if (text.contains(phrase)) count++;
    }
    return count;
  }

  int _countIntensityWords(String text) {
    final words = <String>[
      'now',
      'already',
      'again',
      'always',
      'never',
      'right now',
      'every time',
    ];
    return _countPhraseHits(text, words);
  }

  bool _hasYouBlamePattern(String text) {
    final hasYou = text.contains('you ');
    final blameWords = <String>[
      'never',
      'always',
      'do this',
      'listen',
      'wrong',
      'fault',
      'because of you',
    ];
    return hasYou && _countPhraseHits(text, blameWords) >= 1;
  }

  double _currentVoiceContextScore() {
    if (lastVoiceContextTime == null) return 0.0;

    final secondsOld = DateTime.now().difference(lastVoiceContextTime!).inSeconds;
    if (secondsOld <= 8) return voiceContextScore;
    if (secondsOld >= 25) {
      voiceContextScore = 0.0;
      voiceContextStatus = 'No concerning words detected';
      return 0.0;
    }

    final fade = 1.0 - ((secondsOld - 8) / 17.0);
    return (voiceContextScore * fade).clamp(0.0, 100.0);
  }

  bool _isCalmGuardOwnSpeech(String text) {
  final selfPhrases = <String>[
    'calm down',
    'take a breath',
    'you are in control',
    'warning i can sense rising pressure',
    'i can sense rising pressure',
    'slow down',
    'you are back in calm monitoring mode',
    'back in calm monitoring mode',
    'good job you are back in calm mode',
    'you are back in calm mode',
    'recovery complete',
  ];

  for (final phrase in selfPhrases) {
    if (text.contains(phrase)) {
      return true;
    }
  }

  return false;
}

  bool _hasRepeatedWords(String text) {
    final cleaned = text.replaceAll(RegExp('[^a-zA-Z ]'), ' ');
    final words = cleaned
        .split(' ')
        .where((word) => word.trim().length >= 3)
        .map((word) => word.trim())
        .toList();

    if (words.length < 4) return false;

    final counts = <String, int>{};
    for (final word in words) {
      counts[word] = (counts[word] ?? 0) + 1;
      if ((counts[word] ?? 0) >= 3) return true;
    }
    return false;
  }

  void maybeOpenVoiceCheckFromHeartRate() {
    // Native Android voice service handles HR-rise checks.
    if (isListening || isSpeaking) return;
    if (!isAppInForeground) return;
    if (stage != AlertStage.monitoring) return;

    final learnedHrBaseline =
        personalHrBaselineSamples < 10 ? 72.0 : personalHrBaseline;
    final hrRise = watchHeartRate - learnedHrBaseline;

    if (hrRise < 18) return;

    final now = DateTime.now();
    if (lastAutoVoiceCheckTime != null &&
        now.difference(lastAutoVoiceCheckTime!).inSeconds < 25) {
      return;
    }

    lastAutoVoiceCheckTime = now;
    startTemporaryListeningWindow(seconds: 20, reason: 'HR-rise voice check');
  }

  void updateVoiceBehaviour(double value) {
    processVoiceLevel(value);
  }

  Future<void> simulateWarning() async {
    await flutterTts.stop();
    await stopVoiceListeningHard();

    setState(() {
      // Do NOT reset the engine here. We want Warnings / 5m to increase
      // when you press Simulate Warning multiple times.
      stage = AlertStage.monitoring;
      warning = false;
      triggered = false;
      isSpeaking = false;
      isListening = false;
      voiceWatchMode = false;
      stopVoiceWatchRequested = true;
      allowVoiceCheck = false;
      appStatus = 'Monitoring';
      triggerReason = 'Manual warning test';
      uiWarningHoldStart = null;
      manualWarningTestActive = true;
      manualWarningTestUntil = DateTime.now().add(const Duration(seconds: 12));

      // Tuned warning values: high enough for ORANGE, not high enough for instant RED.
      watchHeartRate = 95;
      stressLevel = 55;
      smoothedWatchStress = 55;
      voiceLevel = 18.0;
      voiceAiScore = 28.0;
      voiceBehaviourStatus = 'Manual warning voice rise';
    });

    addDebugLog(
      'Manual warning test',
      'Temporary ORANGE spike started. Warnings/5m must be kept.',
    );
    scheduleManualWarningAutoCalm();

    await Future.delayed(const Duration(milliseconds: 150));
    evaluateSmartState();
  }

  Future<void> simulateTrigger() async {
    await flutterTts.stop();
    await stopVoiceListeningHard();

    setState(() {
      // Trigger test should force a direct red state.
      stage = AlertStage.monitoring;
      warning = false;
      triggered = false;
      isSpeaking = false;
      isListening = false;
      voiceWatchMode = false;
      stopVoiceWatchRequested = true;
      allowVoiceCheck = false;
      appStatus = 'Monitoring';
      triggerReason = 'Manual trigger test';
      uiWarningHoldStart = null;
      manualWarningTestActive = false;
      manualWarningTestUntil = null;

      watchHeartRate = 132;
      stressLevel = 88;
      smoothedWatchStress = 88;
      voiceLevel = 86.0;
      voiceAiScore = 88.0;
      voiceBehaviourStatus = 'Manual trigger voice escalation';
    });

    addDebugLog(
      'Manual trigger test',
      'RED test started with high HR, risk, and voice score.',
    );

    await Future.delayed(const Duration(milliseconds: 150));
    evaluateSmartState();
  }

  Future<void> resetSignals() async {
    // IMPORTANT: Do NOT call engine.resetEngine() here.
    // Reset Signals must calm the current live signals only.
    // Warnings / 5m memory must stay until the 5-minute window expires naturally.
    cancelWarningAutoCalmTimer();
    cancelOrangeVoiceSampling();
    await flutterTts.stop();
    await stopVoiceListeningHard();

    if (!mounted) return;
    setState(() {
      stage = AlertStage.monitoring;
      warning = false;
      triggered = false;
      cooldownActive = false;
      recoveryActive = false;
      cooldownEndTime = null;
      recoveryEndTime = null;
      appStatus = 'Monitoring';
      triggerReason = 'Signals manually reset. Warning memory kept.';
      heardText = 'No voice sample yet';
      liveStressScore = 20.0;
      aiStressLevel = 20;
      watchHeartRate = 72;
      stressLevel = 20;
      smoothedWatchStress = 20.0;
      voiceLevel = 8.0;
      voiceAiScore = 0.0;
      voiceSpikesLastMinute = 0;
      voiceBehaviourStatus = 'Voice calm';
      voiceContextScore = 0.0;
      voiceContextStatus = 'No concerning words detected';
      lastVoiceContextTime = null;
      lastProcessedVoiceText = '';
      lastProcessedVoiceTextTime = null;
      lastConversationRiskCategory = 'calm';
      voiceConfidenceScore = 0.0;
      pendingVoiceText = '';
      voiceDebounceTimer?.cancel();
      lastAutoVoiceCheckTime = null;
      smartVoiceSessionActive = false;
      smartVoiceSessionEndTime = null;
      uiWarningHoldStart = null;
      manualWarningTestActive = false;
      manualWarningTestUntil = null;
      deepOrangeActive = false;
      deepOrangeStart = null;
    });

    addDebugLog(
      'Reset Signals',
      'Live signals reset to calm. Warnings/5m was kept at ${engine.lastMetrics?.warningCountIn5Min ?? 0}.',
    );

    scheduleEvaluation();
  }

  Widget buildSignalCard({
    required IconData icon,
    required String title,
    required String valueText,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    valueText,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onMinus,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            IconButton(
              onPressed: onPlus,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }


  Widget buildSafetyPrivacyCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Safety & Privacy',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'CalmGuard is wellbeing and de-escalation support. It is not an emergency service, medical diagnosis tool, or safety guarantee.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              'Prototype privacy note: voice is used for short behaviour checks. Do not store or share audio unless a future version clearly asks for consent.',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSetupChecklistCard() {
    final items = <String>[
      speechEnabled ? 'Phone mic permission: ready' : 'Phone mic permission: not ready',
      keepMonitoringWhenScreenLocked
          ? 'Phone screen lock monitoring: best-effort on'
          : 'Phone screen lock monitoring: off',
      'Watch HR/background service: check during watch sleep',
      'Notifications/vibration: check during warning and trigger',
      autoVoiceWindowsEnabled
          ? 'Automatic voice sampling: on'
          : 'Automatic voice sampling: off',
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Setup Checklist',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDebugLogCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        title: const Text(
          'Logs / Debug Screen',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Use this when testing: HR, voice score, reason, and trigger history'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (debugLogs.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No logs yet. Run a warning or trigger test.'),
            )
          else
            ...debugLogs.take(12).map(
              (log) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatLogTime(log.time)} • ${log.event}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(log.details, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                setState(() => debugLogs.clear());
              },
              child: const Text('Clear logs'),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Color get stageColor {
    switch (stage) {
      case AlertStage.warning:
        return Colors.orange;
      case AlertStage.triggered:
        return Colors.red;
      case AlertStage.monitoring:
      default:
        return Colors.green;
    }
  }

  String get stageText {
    switch (stage) {
      case AlertStage.warning:
        return 'ORANGE';
      case AlertStage.triggered:
        return 'RED';
      case AlertStage.monitoring:
      default:
        return 'GREEN';
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = engine.lastMetrics;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CalmGuard'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              color: stageColor.withOpacity(0.12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: stageColor.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          stageText,
                          style: TextStyle(
                            color: stageColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      appStatus,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      triggerReason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                buildInfoChip('Escalation Risk', '$aiStressLevel / 100'),
                buildInfoChip('Risk Score', metrics == null ? '--' : metrics.score.toStringAsFixed(2)),
                buildInfoChip('Warnings / 5m', metrics == null ? '0' : '${metrics.warningCountIn5Min}'),
                buildInfoChip('HR Baseline', metrics == null ? '--' : metrics.hrBaseline.toStringAsFixed(0)),
                buildInfoChip('Risk Baseline', metrics == null ? '--' : metrics.stressBaseline.toStringAsFixed(0)),
                buildInfoChip('Voice Baseline', metrics == null ? '--' : metrics.voiceBaseline.toStringAsFixed(0)),
                buildInfoChip('Voice AI', voiceAiScore.toStringAsFixed(0)),
                buildInfoChip('Voice Spikes', '$voiceSpikesLastMinute/min'),
              ],
            ),
            const SizedBox(height: 18),
            buildSafetyPrivacyCard(),
            const SizedBox(height: 12),
            buildSetupChecklistCard(),
            const SizedBox(height: 12),
            buildDebugLogCard(),
            const SizedBox(height: 18),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Automatic voice sampling',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Uses selective 20-second listening windows during elevated warning states'),
                      value: autoVoiceWindowsEnabled,
                      onChanged: (value) {
                        setState(() => autoVoiceWindowsEnabled = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => startTemporaryListeningWindow(seconds: 20, reason: 'Manual voice check', isManual: true),
                        child: const Text('Run 20-sec voice check now'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Voice text: $heardText', style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 6),
                    Text('Voice AI: $voiceBehaviourStatus', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                      'Note: Escalation Risk is CalmGuard\'s own score. It is not Samsung Health stress.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: ExpansionTile(
                initiallyExpanded: testPanelExpanded,
                onExpansionChanged: (value) {
                  setState(() => testPanelExpanded = value);
                },
                title: const Text(
                  'Developer Testing Panel',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Only for prototype testing before real-world trials'),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                children: [
                  Text(
                    patternStatus,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  buildSignalCard(
                    icon: Icons.favorite,
                    title: 'Heart Rate',
                    valueText: '$watchHeartRate bpm',
                    onMinus: () => updateHeartRateFromWatch(watchHeartRate - 5),
                    onPlus: () => updateHeartRateFromWatch(watchHeartRate + 5),
                  ),
                  buildSignalCard(
                    icon: Icons.bolt,
                    title: 'Manual Risk Test',
                    valueText: '$stressLevel / 100 • testing only',
                    onMinus: () => updateStressFromWatch(stressLevel - 5),
                    onPlus: () => updateStressFromWatch(stressLevel + 5),
                  ),
                  buildSignalCard(
                    icon: Icons.psychology,
                    title: 'Escalation Risk Score',
                    valueText: '$aiStressLevel / 100',
                    onMinus: () {},
                    onPlus: () {},
                  ),
                  buildSignalCard(
                    icon: Icons.mic,
                    title: 'Voice Behaviour Raw',
                    valueText: '${voiceLevel.toStringAsFixed(1)} / 100',
                    onMinus: () => updateVoiceBehaviour(voiceLevel - 5),
                    onPlus: () => updateVoiceBehaviour(voiceLevel + 5),
                  ),
                  buildSignalCard(
                    icon: Icons.record_voice_over,
                    title: 'Voice AI Score',
                    valueText: '${voiceAiScore.toStringAsFixed(0)} / 100 • $voiceSpikesLastMinute spikes/min',
                    onMinus: () {},
                    onPlus: () {},
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: simulateWarning,
                        child: const Text('Simulate Warning'),
                      ),
                      OutlinedButton(
                        onPressed: simulateTrigger,
                        child: const Text('Simulate Trigger'),
                      ),
                      OutlinedButton(
                        onPressed: resetSignals,
                        child: const Text('Reset Signals'),
                      ),
                      OutlinedButton(
                        onPressed: resetSignals,
                        child: const Text('Soft Reset Test'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// VOICE BEHAVIOUR AI v2
// =====================================================

class ConversationRisk {
  final double score;
  final String label;
  final String category;

  const ConversationRisk({
    required this.score,
    required this.label,
    required this.category,
  });
}

class VoiceDecision {
  final double score;
  final int spikesLastMinute;
  final String reason;

  const VoiceDecision({
    required this.score,
    required this.spikesLastMinute,
    required this.reason,
  });
}

class VoiceSample {
  final DateTime time;
  final double level;

  const VoiceSample({
    required this.time,
    required this.level,
  });
}

class VoiceBehaviourEngine {
  double baseline = 8.0;
  double lastLevel = 8.0;
  DateTime? highVoiceStart;

  final List<VoiceSample> _samples = [];
  final List<DateTime> _spikeTimes = [];

  VoiceDecision evaluate({
    required double level,
    required DateTime now,
  }) {
    _cleanup(now);

    final cleanLevel = level.clamp(0.0, 100.0);

    // Learn baseline slowly when voice is calm.
    if (cleanLevel < baseline + 14 && cleanLevel < 35) {
      baseline = baseline + ((cleanLevel - baseline) * 0.05);
    }

    final deltaFromBaseline = (cleanLevel - baseline).clamp(0.0, 100.0);
    final suddenJump = (cleanLevel - lastLevel).clamp(0.0, 100.0);

    final meaningfulVoice = cleanLevel >= 22.0;
    final loudnessScore = meaningfulVoice
        ? (deltaFromBaseline / 48.0).clamp(0.0, 1.0)
        : 0.0;
    final jumpScore = cleanLevel >= 28.0
        ? (suddenJump / 38.0).clamp(0.0, 1.0)
        : 0.0;

    final recentAvg = _recentAverage(now, const Duration(seconds: 8));
    final sustainedScore = recentAvg >= 24.0
        ? ((recentAvg - baseline) / 38.0).clamp(0.0, 1.0)
        : 0.0;

    // Ignore tiny mic startup/background noise. A spike must be meaningful.
    final minimumRealVoiceLevel = 28.0;
    final isSpike = cleanLevel >= minimumRealVoiceLevel &&
        (cleanLevel >= baseline + 32 || suddenJump >= 30);
    if (isSpike) {
      final tooClose = _spikeTimes.isNotEmpty &&
          now.difference(_spikeTimes.last).inMilliseconds < 1200;
      if (!tooClose) {
        _spikeTimes.add(now);
      }
    }

    final spikesLastMinute = _spikeTimes.length;
    final patternScore = (spikesLastMinute / 4.0).clamp(0.0, 1.0);

    if (cleanLevel >= 28.0 && cleanLevel >= baseline + 28) {
      highVoiceStart ??= now;
    } else {
      highVoiceStart = null;
    }

    final sustainedSeconds = highVoiceStart == null
        ? 0
        : now.difference(highVoiceStart!).inSeconds;

    final sustainedTimeBonus = sustainedSeconds >= 8 ? 0.15 : 0.0;

    final combined =
        (loudnessScore * 0.38) +
        (jumpScore * 0.24) +
        (sustainedScore * 0.22) +
        (patternScore * 0.16) +
        sustainedTimeBonus;

    final score = (combined * 100.0).clamp(0.0, 100.0);

    _samples.add(VoiceSample(time: now, level: cleanLevel));
    lastLevel = cleanLevel;

    return VoiceDecision(
      score: score,
      spikesLastMinute: spikesLastMinute,
      reason: _reasonForScore(
        score: score,
        spikes: spikesLastMinute,
        suddenJump: suddenJump,
        sustainedSeconds: sustainedSeconds,
      ),
    );
  }

  double _recentAverage(DateTime now, Duration window) {
    final recent = _samples.where((s) => now.difference(s.time) <= window);
    if (recent.isEmpty) return lastLevel;
    final total = recent.fold<double>(0, (sum, sample) => sum + sample.level);
    return total / recent.length;
  }

  void _cleanup(DateTime now) {
    _samples.removeWhere(
      (sample) => now.difference(sample.time) > const Duration(minutes: 2),
    );
    _spikeTimes.removeWhere(
      (time) => now.difference(time) > const Duration(minutes: 1),
    );
  }

  String _reasonForScore({
    required double score,
    required int spikes,
    required double suddenJump,
    required int sustainedSeconds,
  }) {
    if (score >= 75) {
      return 'Strong voice escalation detected';
    }
    if (score >= 55) {
      return 'Voice behaviour elevated';
    }
    if (spikes >= 4) {
      return 'Repeated voice spikes detected';
    }
    if (suddenJump >= 18) {
      return 'Sudden voice change detected';
    }
    if (sustainedSeconds >= 6) {
      return 'Voice intensity staying high';
    }
    return 'Voice calm';
  }

  void reset() {
    baseline = 8.0;
    lastLevel = 8.0;
    highVoiceStart = null;
    _samples.clear();
    _spikeTimes.clear();
  }
}

// =====================================================
// SMART ADAPTIVE ENGINE
// =====================================================

enum EngineAction {
  none,
  warning,
  trigger,
  reset,
}

class EngineDecision {
  final EngineAction action;
  final String reason;
  final SmartMetrics metrics;

  const EngineDecision({
    required this.action,
    required this.reason,
    required this.metrics,
  });
}

class SmartMetrics {
  final double score;
  final double hrBaseline;
  final double stressBaseline;
  final double voiceBaseline;
  final int warningCountIn5Min;

  const SmartMetrics({
    required this.score,
    required this.hrBaseline,
    required this.stressBaseline,
    required this.voiceBaseline,
    required this.warningCountIn5Min,
  });
}

class SmartSnapshot {
  final DateTime time;
  final double heartRate;
  final double stress;
  final double voice;
  final double score;

  SmartSnapshot({
    required this.time,
    required this.heartRate,
    required this.stress,
    required this.voice,
    required this.score,
  });
}

class SmartTriggerEngine {
  double hrBaseline = 72;
  double stressBaseline = 20;
  double voiceBaseline = 8;

  final List<SmartSnapshot> _history = [];
  final List<DateTime> _warningTimes = [];

  DateTime? _warningStart;
  DateTime? _lastWarningAddedTime;
  DateTime? _triggerStart;
  DateTime? _calmStart;

  SmartMetrics? lastMetrics;

  EngineDecision evaluate({
    required double heartRate,
    required double stress,
    required double voice,
    required DateTime now,
    required AlertStage currentStage,
  }) {
    _cleanup(now);

    if (currentStage == AlertStage.monitoring) {
      final provisionalScore = _quickScore(
        heartRate: heartRate,
        stress: stress,
        voice: voice,
      );

      if (provisionalScore < 0.38) {
        hrBaseline = _ema(hrBaseline, heartRate, 0.035);
        stressBaseline = _ema(stressBaseline, stress, 0.035);
        voiceBaseline = _ema(voiceBaseline, voice, 0.045);
      }
    }

    final hrNorm = _positiveNormalized(heartRate - hrBaseline, 9, 35);
    final stressNorm = _positiveNormalized(stress - stressBaseline, 8, 34);
    final voiceNorm = _positiveNormalized(voice - voiceBaseline, 7, 34);

    final hrTrend = _trendBoost(
      current: heartRate,
      shortAvg: _avgRecent((s) => s.heartRate, 4, fallback: hrBaseline),
      longAvg: _avgRecent((s) => s.heartRate, 12, fallback: hrBaseline),
      scale: 18,
    );

    final stressTrend = _trendBoost(
      current: stress,
      shortAvg: _avgRecent((s) => s.stress, 4, fallback: stressBaseline),
      longAvg: _avgRecent((s) => s.stress, 12, fallback: stressBaseline),
      scale: 18,
    );

    final voiceTrend = _trendBoost(
      current: voice,
      shortAvg: _avgRecent((s) => s.voice, 4, fallback: voiceBaseline),
      longAvg: _avgRecent((s) => s.voice, 12, fallback: voiceBaseline),
      scale: 18,
    );

    final elevatedCount = [hrNorm, stressNorm, voiceNorm].where((v) => v >= 0.48).length;
    final confirmedByVoice = voiceNorm >= 0.38 && (hrNorm >= 0.30 || stressNorm >= 0.35);
    final confirmedByBody = hrNorm >= 0.45 && stressNorm >= 0.45;
    final voiceStressStrong = voiceNorm >= 0.55 && stressNorm >= 0.45;
    final hrConversationWarning = hrNorm >= 0.42 && voiceNorm >= 0.50;

    // Exercise-style filter: HR is elevated but voice and stress are calm.
    final likelyExercise = hrNorm >= 0.58 && stressNorm < 0.32 && voiceNorm < 0.28;

    final combinedScore =
        (hrNorm * 0.24) +
        (stressNorm * 0.32) +
        (voiceNorm * 0.34) +
        (hrTrend * 0.05) +
        (stressTrend * 0.07) +
        (voiceTrend * 0.10) +
        _comboBonus(hrNorm, stressNorm, voiceNorm) -
        (likelyExercise ? 0.18 : 0.0);

    final score = combinedScore.clamp(0.0, 1.0);

    _history.add(
      SmartSnapshot(
        time: now,
        heartRate: heartRate,
        stress: stress,
        voice: voice,
        score: score,
      ),
    );

    lastMetrics = SmartMetrics(
      score: score,
      hrBaseline: hrBaseline,
      stressBaseline: stressBaseline,
      voiceBaseline: voiceBaseline,
      warningCountIn5Min: _warningTimes.length,
    );

    final calmEnough =
        score < 0.30 &&
        heartRate <= hrBaseline + 10 &&
        stress <= stressBaseline + 10 &&
        voice <= voiceBaseline + 12;

    // AI Stress v2 warning logic:
    // HR alone does not warn unless it is extreme. We need confirmation.
    final shouldWarn = !likelyExercise &&
        (score >= 0.52 ||
            confirmedByBody ||
            confirmedByVoice ||
            hrConversationWarning ||
            voiceStressStrong ||
            elevatedCount >= 2);

    if (currentStage == AlertStage.monitoring && shouldWarn) {
      _warningStart ??= now;
      _addWarningTime(now);

      return EngineDecision(
        action: EngineAction.warning,
        reason: _buildReason(
          score: score,
          hrNorm: hrNorm,
          stressNorm: stressNorm,
          voiceNorm: voiceNorm,
          warningCount5m: _warningTimes.length,
          prefix: 'Warning stage',
          likelyExercise: likelyExercise,
        ),
        metrics: lastMetrics!,
      );
    }

    final warningHeldSeconds =
        currentStage == AlertStage.warning && _warningStart != null
            ? now.difference(_warningStart!).inSeconds
            : 0;

    final sustainedWarning =
        currentStage == AlertStage.warning &&
        _warningStart != null &&
        warningHeldSeconds >= 22 &&
        score >= 0.80 &&
        (elevatedCount >= 2 || voiceStressStrong);

    final repeatedPatternTrigger =
        currentStage == AlertStage.warning &&
        _warningStart != null &&
        warningHeldSeconds >= 12 &&
        _warningTimes.length >= 3 &&
        score >= 0.78 &&
        (elevatedCount >= 2 || voiceStressStrong);

    final strongAllRound = hrNorm >= 0.66 && stressNorm >= 0.62 && voiceNorm >= 0.62;

    // RED should not fire from one mild phrase.
    // It now needs a short confirmation window, repeated pattern, or very strong all-signal risk.
    final instantTrigger = !likelyExercise &&
        currentStage == AlertStage.warning &&
        _warningStart != null &&
        warningHeldSeconds >= 7 &&
        (score >= 0.95 ||
            (strongAllRound && score >= 0.88) ||
            (voiceStressStrong && stressNorm >= 0.55 && score >= 0.90));

    if (instantTrigger || sustainedWarning || repeatedPatternTrigger) {
      _triggerStart ??= now;
      _calmStart = null;

      final warningCount5m = _warningTimes.length;
      final triggerText = repeatedPatternTrigger
          ? 'Triggered: repeated escalation pattern detected ($warningCount5m warnings in 5 minutes)'
          : _buildReason(
              score: score,
              hrNorm: hrNorm,
              stressNorm: stressNorm,
              voiceNorm: voiceNorm,
              warningCount5m: warningCount5m,
              prefix: 'Triggered',
              likelyExercise: likelyExercise,
            );

      return EngineDecision(
        action: EngineAction.trigger,
        reason: triggerText,
        metrics: lastMetrics!,
      );
    }

    if (currentStage == AlertStage.warning || currentStage == AlertStage.triggered) {
      if (calmEnough) {
        _calmStart ??= now;
      } else {
        _calmStart = null;
      }

      final resetSeconds = currentStage == AlertStage.triggered ? 8 : 5;

      if (_calmStart != null &&
          now.difference(_calmStart!).inSeconds >= resetSeconds) {
        _warningStart = null;
        _triggerStart = null;
        _calmStart = null;

        return EngineDecision(
          action: EngineAction.reset,
          reason: 'Signals returned close to baseline and stayed calm long enough',
          metrics: lastMetrics!,
        );
      }
    }

    if (currentStage == AlertStage.monitoring) {
      _warningStart = null;
      _triggerStart = null;
      _calmStart = null;
    }

    return EngineDecision(
      action: EngineAction.none,
      reason: _buildNeutralReason(score, hrNorm, stressNorm, voiceNorm, likelyExercise),
      metrics: lastMetrics!,
    );
  }

  void _addWarningTime(DateTime now) {
    // Count one meaningful ORANGE event, not every evaluation tick.
    // This prevents warning spam while the same elevated situation is still settling.
    if (_lastWarningAddedTime != null &&
        now.difference(_lastWarningAddedTime!).inSeconds < 20) {
      return;
    }
    _lastWarningAddedTime = now;
    _warningTimes.add(now);
  }

  void _cleanup(DateTime now) {
    _history.removeWhere(
      (item) => now.difference(item.time) > const Duration(minutes: 10),
    );
    _warningTimes.removeWhere(
      (time) => now.difference(time) > const Duration(minutes: 5),
    );
  }

  double _quickScore({
    required double heartRate,
    required double stress,
    required double voice,
  }) {
    final hr = _positiveNormalized(heartRate - hrBaseline, 9, 35);
    final st = _positiveNormalized(stress - stressBaseline, 8, 34);
    final vo = _positiveNormalized(voice - voiceBaseline, 7, 34);
    return (hr * 0.24) + (st * 0.32) + (vo * 0.34) + _comboBonus(hr, st, vo);
  }

  double _ema(double oldValue, double newValue, double alpha) {
    return oldValue + ((newValue - oldValue) * alpha);
  }

  double _positiveNormalized(double delta, double quietZone, double fullScale) {
    if (delta <= quietZone) return 0.0;
    final adjusted = delta - quietZone;
    return (adjusted / fullScale).clamp(0.0, 1.0);
  }

  double _trendBoost({
    required double current,
    required double shortAvg,
    required double longAvg,
    required double scale,
  }) {
    final risingVsShort = (current - shortAvg) / scale;
    final risingVsLong = (current - longAvg) / scale;
    final combined = (risingVsShort * 0.6) + (risingVsLong * 0.4);
    return combined.clamp(0.0, 1.0);
  }

  double _avgRecent(
    double Function(SmartSnapshot s) selector,
    int count, {
    required double fallback,
  }) {
    if (_history.isEmpty) return fallback;
    final start = math.max(0, _history.length - count);
    final slice = _history.sublist(start);
    if (slice.isEmpty) return fallback;
    final total = slice.fold<double>(0, (sum, item) => sum + selector(item));
    return total / slice.length;
  }

  double _comboBonus(double hrNorm, double stressNorm, double voiceNorm) {
    int elevated = 0;
    if (hrNorm >= 0.48) elevated++;
    if (stressNorm >= 0.48) elevated++;
    if (voiceNorm >= 0.48) elevated++;

    if (elevated == 3) return 0.16;
    if (elevated == 2) return 0.08;
    return 0.0;
  }

  String _buildReason({
    required double score,
    required double hrNorm,
    required double stressNorm,
    required double voiceNorm,
    required int warningCount5m,
    required String prefix,
    required bool likelyExercise,
  }) {
    final parts = <String>[];

    if (hrNorm >= 0.55) parts.add('heart rate elevated');
    if (stressNorm >= 0.55) parts.add('escalation risk elevated');
    if (voiceNorm >= 0.55) parts.add('voice behaviour changed');

    if (parts.isEmpty) {
      parts.add('multiple signals rising');
    }

    if (likelyExercise) {
      parts.add('exercise-style HR filtered');
    }

    return '$prefix: ${parts.join(', ')}. Risk ${score.toStringAsFixed(2)}. Warnings in 5 min: $warningCount5m';
  }

  String _buildNeutralReason(
    double score,
    double hrNorm,
    double stressNorm,
    double voiceNorm,
    bool likelyExercise,
  ) {
    if (likelyExercise) {
      return 'Monitoring: heart rate high but voice/stress look calm';
    }

    if (score < 0.28) {
      return 'All signals normal';
    }

    final softParts = <String>[];
    if (hrNorm > 0.25) softParts.add('heart rate rising');
    if (stressNorm > 0.25) softParts.add('escalation risk rising');
    if (voiceNorm > 0.25) softParts.add('voice behaviour changing');

    if (softParts.isEmpty) {
      return 'Monitoring adaptive patterns';
    }

    return 'Monitoring: ${softParts.join(', ')}';
  }

  void resetEngine() {
    _history.clear();
    _warningTimes.clear();
    _warningStart = null;
    _lastWarningAddedTime = null;
    _triggerStart = null;
    _calmStart = null;
    lastMetrics = null;
  }
}
