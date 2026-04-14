import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vibration/vibration.dart';

void main() {
  runApp(const CalmGuardApp());
}

class CalmGuardApp extends StatelessWidget {
  const CalmGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CalmGuard',
      home: const CalmGuardHome(),
    );
  }
}

class CalmGuardHome extends StatefulWidget {
  const CalmGuardHome({super.key});

  @override
  State<CalmGuardHome> createState() => _CalmGuardHomeState();
}

class _CalmGuardHomeState extends State<CalmGuardHome> {
  final FlutterTts flutterTts = FlutterTts();
  final stt.SpeechToText speech = stt.SpeechToText();

  static const MethodChannel watchChannel = MethodChannel('calmguard/watch');

  bool triggered = false;
  bool warning = false;
  bool isListening = false;
  bool isSpeaking = false;
  bool warningSpoken = false;
  bool showTestingPanel = false;

  String triggerReason = 'All signals normal';
  String appStatus = 'Monitoring';
  String heardText = 'Nothing heard yet';

  int heartRate = 72;
  int stressLevel = 20;
  double voiceStress = 20;

  final int heartRateThreshold = 100;
  final int stressLevelThreshold = 70;
  final double voiceStressThreshold = 70;

  int heartRateHighTime = 0;
  int stressHighTime = 0;
  int voiceHighTime = 0;

  final int holdThreshold = 2;

  Timer? monitorTimer;
  Timer? voiceCooldownTimer;

  DateTime? micBlockedUntil;
  DateTime? watchOverrideUntil;

  bool get isMicBlocked {
    if (micBlockedUntil == null) return false;
    return DateTime.now().isBefore(micBlockedUntil!);
  }

  bool get isWatchOverrideActive {
    if (watchOverrideUntil == null) return false;
    return DateTime.now().isBefore(watchOverrideUntil!);
  }

  @override
  void initState() {
    super.initState();
    setupTts();
    setupWatchChannel();
    startMonitoring();
    startVoiceCooldown();
  }

  Future<void> setupTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.45);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
    await flutterTts.awaitSpeakCompletion(true);

    flutterTts.setStartHandler(() {
      if (!mounted) return;
      setState(() {
        isSpeaking = true;
        appStatus = 'Speaking';
      });
    });

    flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() {
        isSpeaking = false;
        appStatus = triggered
            ? 'Triggered'
            : warning
                ? 'Warning'
                : 'Monitoring';
      });
    });

    flutterTts.setCancelHandler(() {
      if (!mounted) return;
      setState(() {
        isSpeaking = false;
        appStatus = triggered
            ? 'Triggered'
            : warning
                ? 'Warning'
                : 'Monitoring';
      });
    });

    flutterTts.setErrorHandler((message) {
      if (!mounted) return;
      setState(() {
        isSpeaking = false;
        appStatus = triggered
            ? 'Triggered'
            : warning
                ? 'Warning'
                : 'Monitoring';
      });
    });
  }

  void setupWatchChannel() {
    watchChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'watch_warning':
        case 'watchWarning':
          handleWatchWarning();
          break;

        case 'watch_trigger':
        case 'watchTrigger':
          handleWatchTrigger();
          break;

        case 'watch_reset':
        case 'watchReset':
          handleWatchReset();
          break;

        default:
          break;
      }
      return;
    });
  }

  Future<void> speakMessage(String message) async {
    if (isListening) {
      await speech.stop();
      if (mounted) {
        setState(() {
          isListening = false;
        });
      }
    }

    micBlockedUntil = DateTime.now().add(const Duration(seconds: 5));

    await flutterTts.stop();
    await flutterTts.speak(message);

    micBlockedUntil = DateTime.now().add(const Duration(seconds: 2));
  }

  void startMonitoring() {
    monitorTimer?.cancel();
    monitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      checkTrigger();
    });
  }

  void startVoiceCooldown() {
    voiceCooldownTimer?.cancel();
    voiceCooldownTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (voiceStress > 0 && !isListening && !isSpeaking) {
        setState(() {
          voiceStress -= 5;
          if (voiceStress < 0) voiceStress = 0;
        });
      }
    });
  }

  Future<void> startTemporaryListeningWindow() async {
    if (isListening || isSpeaking || isMicBlocked) return;

    bool available = await speech.initialize();

    if (!available) {
      setState(() {
        heardText = 'Speech recognition not available on this device.';
      });
      return;
    }

    setState(() {
      isListening = true;
      heardText = 'Listening for voice check...';
      appStatus = 'Checking voice';
    });

    speech.listen(
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      onResult: (result) {
        if (!mounted) return;
        if (isSpeaking || isMicBlocked) return;

        final words = result.recognizedWords;

        setState(() {
          heardText = words.isEmpty ? 'Listening for voice check...' : words;
        });

        final lowerWords = words.toLowerCase();

        if (lowerWords.contains('stop') ||
            lowerWords.contains('shut up') ||
            lowerWords.contains('leave me alone') ||
            lowerWords.contains('angry') ||
            lowerWords.contains('pissed') ||
            lowerWords.contains('hate')) {
          setState(() {
            voiceStress += 20;
            if (voiceStress > 100) voiceStress = 100;
          });
        }

        if (lowerWords.contains('calm') ||
            lowerWords.contains('relax') ||
            lowerWords.contains('okay') ||
            lowerWords.contains('breathe')) {
          setState(() {
            voiceStress -= 10;
            if (voiceStress < 0) voiceStress = 0;
          });
        }
      },
    );

    Future.delayed(const Duration(seconds: 8), () async {
      if (!mounted) return;
      await speech.stop();
      if (!mounted) return;

      setState(() {
        isListening = false;
        appStatus = isSpeaking
            ? 'Speaking'
            : triggered
                ? 'Triggered'
                : warning
                    ? 'Warning'
                    : 'Monitoring';
      });
    });
  }

  void handleWatchWarning() {
    if (!mounted) return;

    watchOverrideUntil = DateTime.now().add(const Duration(seconds: 8));

    setState(() {
      warning = true;
      triggered = false;
      warningSpoken = false;
      triggerReason = 'Watch detected rising stress';
      appStatus = 'Warning';
      heardText = 'Watch warning received.';
    });

    Vibration.vibrate(duration: 300);
  }

  void handleWatchTrigger() {
    if (!mounted) return;

    watchOverrideUntil = DateTime.now().add(const Duration(seconds: 12));

    setState(() {
      heartRate = 110;
      triggerReason = 'Watch detected rising state';
      warning = false;
      triggered = true;
      appStatus = 'Triggered';
      heardText = 'Watch trigger received. Opening voice check...';
      warningSpoken = false;
    });

    speakMessage(
      'Watch alert received. Calm down. Take a breath. You are in control.',
    );
    Vibration.vibrate(duration: 800);

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      startTemporaryListeningWindow();
    });
  }

  void handleWatchReset() {
    if (!mounted) return;

    watchOverrideUntil = DateTime.now().add(const Duration(seconds: 10));

    setState(() {
      triggered = false;
      warning = false;
      warningSpoken = false;
      triggerReason = 'All signals normal';
      appStatus = 'Monitoring';
      heardText = 'Watch reset received.';
      heartRateHighTime = 0;
      stressHighTime = 0;
      voiceHighTime = 0;
      voiceStress = 20;
      stressLevel = 20;
      heartRate = 72;
    });

    flutterTts.stop();
    speech.stop();

    setState(() {
      isListening = false;
      isSpeaking = false;
    });
  }

  void updateHeartRateFromWatch(int value) {
    if (!mounted) return;
    setState(() {
      heartRate = value.clamp(40, 220);
    });
  }

  void increaseHeartRate() {
    setState(() {
      heartRate += 10;
      if (heartRate > 200) heartRate = 200;
    });
  }

  void decreaseHeartRate() {
    setState(() {
      heartRate -= 10;
      if (heartRate < 40) heartRate = 40;
    });
  }

  void increaseStressLevel() {
    setState(() {
      stressLevel += 10;
      if (stressLevel > 100) stressLevel = 100;
    });
  }

  void decreaseStressLevel() {
    setState(() {
      stressLevel -= 10;
      if (stressLevel < 0) stressLevel = 0;
    });
  }

  void increaseVoiceStress() {
    setState(() {
      voiceStress += 10;
      if (voiceStress > 100) voiceStress = 100;
    });
  }

  void decreaseVoiceStress() {
    setState(() {
      voiceStress -= 10;
      if (voiceStress < 0) voiceStress = 0;
    });
  }

  void resetAll() {
    setState(() {
      heartRate = 72;
      stressLevel = 20;
      voiceStress = 20;
      heartRateHighTime = 0;
      stressHighTime = 0;
      voiceHighTime = 0;
      triggered = false;
      warning = false;
      isListening = false;
      isSpeaking = false;
      warningSpoken = false;
      triggerReason = 'All signals normal';
      appStatus = 'Monitoring';
      heardText = 'Nothing heard yet';
      micBlockedUntil = null;
      watchOverrideUntil = null;
    });

    flutterTts.stop();
    speech.stop();
  }

  void checkTrigger() {
    if (isWatchOverrideActive) {
      return;
    }

    if (heartRate >= heartRateThreshold) {
      heartRateHighTime++;
    } else {
      heartRateHighTime = 0;
    }

    if (stressLevel >= stressLevelThreshold) {
      stressHighTime++;
    } else {
      stressHighTime = 0;
    }

    if (voiceStress >= voiceStressThreshold) {
      voiceHighTime++;
    } else {
      voiceHighTime = 0;
    }

    final bool bodyRiskHigh =
        heartRateHighTime >= holdThreshold || stressHighTime >= holdThreshold;

    if ((heartRate >= heartRateThreshold ||
            stressLevel >= stressLevelThreshold) &&
        !isListening &&
        !isSpeaking &&
        !isMicBlocked) {
      startTemporaryListeningWindow();
    }

    String newReason = 'All signals normal';
    String triggerMessage = 'Calm down. Take a breath. You are in control.';
    bool shouldTrigger = false;

    if (bodyRiskHigh && voiceHighTime == 0) {
      warning = true;
      newReason = 'Body signals rising';

      if (!triggered) {
        appStatus = isListening ? 'Checking voice' : 'Warning';
      }

      if (!warningSpoken) {
        warningSpoken = true;
        speakMessage("Hey, take it easy. Breathe slowly.");
        Vibration.vibrate(duration: 300);
      }
    } else {
      warning = false;
      warningSpoken = false;
    }

    if (bodyRiskHigh && voiceHighTime >= 1) {
      shouldTrigger = true;

      if (heartRateHighTime >= holdThreshold &&
          stressHighTime >= holdThreshold) {
        newReason = 'High heart rate, high stress, and tense voice';
        triggerMessage =
            'Your body and voice both show stress. Pause and take a deep breath.';
      } else if (heartRateHighTime >= holdThreshold) {
        newReason = 'High heart rate confirmed by voice';
        triggerMessage =
            'Your heart rate is high and your voice sounds tense. Slow down and breathe.';
      } else if (stressHighTime >= holdThreshold) {
        newReason = 'High stress confirmed by voice';
        triggerMessage =
            'Your stress is high and your voice sounds tense. Pause and breathe slowly.';
      }
    }

    if (shouldTrigger && !triggered) {
      setState(() {
        triggered = true;
        warning = false;
        triggerReason = newReason;
        appStatus = 'Triggered';
      });

      speakMessage(triggerMessage);
      Vibration.vibrate(duration: 800);
    } else if (!shouldTrigger &&
        triggered &&
        triggerReason != 'Watch detected rising state') {
      setState(() {
        triggered = false;
        triggerReason = 'All signals normal';
        appStatus = isListening
            ? 'Checking voice'
            : warning
                ? 'Warning'
                : 'Monitoring';
      });

      speakMessage("Good job. You are back in calm mode.");
    } else {
      setState(() {
        if (!triggered) {
          triggerReason = newReason;
          appStatus = isListening
              ? 'Checking voice'
              : warning
                  ? 'Warning'
                  : 'Monitoring';
        }
      });
    }
  }

  String getMainHeading() {
    if (triggered) return 'TRIGGER DETECTED';
    if (warning) return 'WARNING';
    return 'CALM MODE';
  }

  String getGuidanceMessage() {
    if (triggered) return 'Pause now and take a slow deep breath.';
    if (warning) return 'Your body signals are rising. Slow things down.';
    return 'You are steady. Keep breathing calmly.';
  }

  @override
  void dispose() {
    monitorTimer?.cancel();
    voiceCooldownTimer?.cancel();
    flutterTts.stop();
    speech.stop();
    super.dispose();
  }

  Widget buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSignalCard(String title, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildTestButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }

  Widget buildControlRow({
    required String label,
    required String emoji,
    required int value,
    required VoidCallback onIncrease,
    required VoidCallback onDecrease,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            '$emoji  $label',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            onPressed: onIncrease,
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: triggered
          ? Colors.red
          : warning
              ? Colors.orange
              : Colors.green,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                getMainHeading(),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                triggerReason,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: buildInfoChip('Status', appStatus)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: buildInfoChip(
                      'Mic',
                      isListening ? 'Listening' : 'Off',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  getGuidanceMessage(),
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Live Signals',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              buildSignalCard('Heart Rate', '$heartRate bpm'),
              buildSignalCard('Stress Level', '$stressLevel'),
              buildSignalCard('Voice Stress', voiceStress.toStringAsFixed(0)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Heard Voice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      heardText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  setState(() {
                    showTestingPanel = !showTestingPanel;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Testing Panel',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(
                        showTestingPanel
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: showTestingPanel
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Use these controls to simulate signal changes while building CalmGuard.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),
                      buildControlRow(
                        label: 'Heart Rate',
                        emoji: '❤️',
                        value: heartRate,
                        onIncrease: increaseHeartRate,
                        onDecrease: decreaseHeartRate,
                      ),
                      buildControlRow(
                        label: 'Stress Level',
                        emoji: '⚡',
                        value: stressLevel,
                        onIncrease: increaseStressLevel,
                        onDecrease: decreaseStressLevel,
                      ),
                      buildControlRow(
                        label: 'Voice Stress',
                        emoji: '🎤',
                        value: voiceStress.toInt(),
                        onIncrease: increaseVoiceStress,
                        onDecrease: decreaseVoiceStress,
                      ),
                      const SizedBox(height: 12),
                      buildTestButton(
                        'Simulate Watch HR = 110',
                        () {
                          updateHeartRateFromWatch(110);
                        },
                      ),
                      const SizedBox(height: 12),
                      buildTestButton(
                        'Simulate Watch Warning',
                        handleWatchWarning,
                      ),
                      const SizedBox(height: 12),
                      buildTestButton(
                        'Simulate Watch Trigger',
                        handleWatchTrigger,
                      ),
                      const SizedBox(height: 12),
                      buildTestButton(
                        'Simulate Watch Reset',
                        handleWatchReset,
                      ),
                      const SizedBox(height: 12),
                      buildTestButton('Reset All', resetAll),
                    ],
                  ),
                ),
                secondChild: const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}