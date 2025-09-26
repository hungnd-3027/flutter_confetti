import 'dart:math';
import 'dart:ui';

import 'package:confetti/src/constants.dart';
import 'package:confetti/src/helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vmath;

import 'enums/blast_directionality.dart';

/// {@template particle_system_status}
/// Represents the current status of the particle system.
///
/// This enum has three possible values:
/// - `started`: the particle system has been started and is currently running.
/// - `finished`: the particle system has finished running and is no longer active.
/// - `stopped`: the particle system has been manually stopped and is no longer active.
/// {@endtemplate}
enum ParticleSystemStatus {
  started,
  finished,
  stopped,
}

class ParticleSystem extends ChangeNotifier {
  ParticleSystem({
    required double emissionFrequency,
    required int numberOfParticles,
    required double maxBlastForce,
    required double minBlastForce,
    required double blastDirection,
    required BlastDirectionality blastDirectionality,
    required List<Color>? colors,
    required Size minimumSize,
    required Size maximumSize,
    required double particleDrag,
    required double gravity,
    Path Function(Size size)? createParticlePath,
    bool useLinearColor = false,
    Gradient? gradient,
  })  : assert(maxBlastForce > 0 &&
            minBlastForce > 0 &&
            emissionFrequency >= 0 &&
            emissionFrequency <= 1 &&
            numberOfParticles > 0 &&
            minimumSize.width > 0 &&
            minimumSize.height > 0 &&
            maximumSize.width > 0 &&
            maximumSize.height > 0 &&
            minimumSize.width <= maximumSize.width &&
            minimumSize.height <= maximumSize.height &&
            particleDrag >= 0.0 &&
            particleDrag <= 1 &&
            minimumSize.height <= maximumSize.height),
        assert(gravity >= 0 && gravity <= 1),
        _blastDirection = blastDirection,
        _blastDirectionality = blastDirectionality,
        _gravity = gravity,
        _maxBlastForce = maxBlastForce,
        _minBlastForce = minBlastForce,
        _frequency = emissionFrequency,
        _numberOfParticles = numberOfParticles,
        _colors = colors,
        _minimumSize = minimumSize,
        _maximumSize = maximumSize,
        _particleDrag = particleDrag,
        _rand = Random(),
        _createParticlePath = createParticlePath;

  ParticleSystemStatus? _particleSystemStatus;

  final List<Particle> _particles = [];

  /// A frequency between 0 and 1 to determine how often the emitter
  /// should emit new particles.
  final double _frequency;
  final int _numberOfParticles;
  final double _maxBlastForce;
  final double _minBlastForce;
  final double _blastDirection;
  final BlastDirectionality _blastDirectionality;
  final double _gravity;
  final List<Color>? _colors;
  final Size _minimumSize;
  final Size _maximumSize;
  final double _particleDrag;
  final Path Function(Size size)? _createParticlePath;

  Offset _particleSystemPosition = Offset.zero;
  Size _screenSize = Size.zero;

  late double _bottomBorder;
  late double _rightBorder;
  late double _leftBorder;

  final Random _rand;
  int _directionalSequenceIndex = 0;

  static const double _directionalConeSpread = pi / 2;

  set particleSystemPosition(Offset position) {
    _particleSystemPosition = position;
  }

  set screenSize(Size size) {
    _screenSize = size;
    // needs to be called here to only set the borders once
    _setScreenBorderPositions();
    // Update screen size for existing particles
    _updateParticlesScreenSize(size);
  }

  void _updateParticlesScreenSize(Size size) {
    for (final particle in _particles) {
      particle._updateScreenSize(size);
    }
  }

  void stopParticleEmission({bool clearAllParticles = false}) {
    _particleSystemStatus = ParticleSystemStatus.stopped;
    if (clearAllParticles) {
      _particles.clear();
    }
  }

  void startParticleEmission() {
    _particleSystemStatus = ParticleSystemStatus.started;
  }

  void finishParticleEmission() {
    _particles.clear();
    _particleSystemStatus = ParticleSystemStatus.finished;
  }

  /// List of all [Particle]s.
  List<Particle> get particles => _particles;

  /// The number of particles in memory. Consists of active and deactive
  /// particles.
  ///
  /// Old particles that are no longer visible are deactivated, and reused when
  /// needed. New particles are only created when there is an insuffient number
  /// of deactive particles in memory.
  int get numberOfParticles => _particles.length;

  /// The number of active particles currently animating and visible.
  ///
  /// This is not the same as [numberOfParticles].
  int get activeNumberOfParticles => _particles.fold(
        0,
        (previousValue, element) {
          if (element.active) {
            return previousValue + 1;
          } else {
            return previousValue;
          }
        },
      );

  /// {@macro particle_system_status}
  ParticleSystemStatus? get particleSystemStatus => _particleSystemStatus;

  /// Update the particle system animation by moving it forward.
  void update(double deltaTime, {bool pauseEmission = false}) {
    if (_particleSystemStatus != ParticleSystemStatus.finished) {
      _updateParticles(deltaTime);
    }

    if ((_particleSystemStatus == ParticleSystemStatus.stopped) &&
        _particles.isEmpty) {
      finishParticleEmission();
      notifyListeners();
    }

    // Return early if pauseEmission is true
    if (pauseEmission) return;

    if (_particleSystemStatus == ParticleSystemStatus.started) {
      // If there are no particles then immediately generate particles
      // This also ensures that particles are emitted on the first frame
      if (particles.isEmpty) {
        _addParticles(_particles, number: _numberOfParticles);
        return;
      }

      // Determines whether to generate new particles based on the [frequency]
      final chanceToGenerate = _rand.nextDouble();
      if (chanceToGenerate < _frequency) {
        _addParticles(_particles, number: _numberOfParticles);
      }
    }
  }

  void _setScreenBorderPositions() {
    _bottomBorder = _screenSize.height * 1.1;
    _rightBorder = _screenSize.width * 1.1;
    _leftBorder = _screenSize.width - _rightBorder;
  }

  void _updateParticles(double deltaTime) {
    // remove particles from memory if system is stopped, update and return
    if (_particleSystemStatus == ParticleSystemStatus.stopped) {
      _particles
          .removeWhere((particle) => _isOutsideOfBorder(particle.location));
      for (final particle in _particles) {
        particle.update(deltaTime);
      }
      return;
    }

    // deactivate particles no longer visible and update rest
    for (final particle in _particles) {
      if (_isOutsideOfBorder(particle.location)) {
        particle.deactivate();
        continue;
      }
      particle.update(deltaTime);
    }
  }

  bool _isOutsideOfBorder(Offset particleLocation) {
    final globalParticlePosition = particleLocation + _particleSystemPosition;
    return (globalParticlePosition.dy >= _bottomBorder) ||
        (globalParticlePosition.dx >= _rightBorder) ||
        (globalParticlePosition.dx <= _leftBorder);
  }

  void _addParticles(List<Particle> particles, {int number = 1}) {
    int count = 0;

    for (final particle in particles) {
      if (!particle.active) {
        particle.reactivate();
        count++;
        if (count == number) {
          return; // exit early, no need to generate more particles
        }
      }
    }

    // create more particles not enough in memory
    for (var i = 0; i < number - count; i++) {
      particles.add(
        Particle(
          _randomColor(),
          _randomSize(),
          _gravity,
          _particleDrag,
          _createParticlePath,
          generateParticleForceCallback: _generateParticleForce,
          screenSize: _screenSize,
          emitterPosition: _particleSystemPosition,
        ),
      );
    }
  }

  double get _randomBlastDirection =>
      vmath.radians(Random().nextInt(359).toDouble());

  vmath.Vector2 _generateParticleForce() {
    var blastDirection = _blastDirection;
    if (_blastDirectionality == BlastDirectionality.explosive) {
      blastDirection = _randomBlastDirection;
    } else {
      blastDirection = _blastDirection + _nextDirectionalConeOffset();
    }

    final blastRadius = Helper.randomize(_minBlastForce, _maxBlastForce);

    final x = blastRadius * cos(blastDirection);
    final y = blastRadius * sin(blastDirection);
    return vmath.Vector2(x, y);
  }

  double _nextDirectionalConeOffset() {
    if (_numberOfParticles <= 1) {
      _directionalSequenceIndex++;
      return 0;
    }

    final step = _directionalConeSpread / (_numberOfParticles - 1);
    final indexInSequence = _directionalSequenceIndex % _numberOfParticles;
    _directionalSequenceIndex++;

    final baseOffset = -_directionalConeSpread / 2 + indexInSequence * step;
    final jitter =
        step == 0 ? 0.0 : Helper.randomize(-step * 0.15, step * 0.15);

    final offset = (baseOffset + jitter)
        .clamp(-_directionalConeSpread / 2, _directionalConeSpread / 2)
        .toDouble();

    return offset;
  }

  Color _randomColor() {
    if (_colors != null) {
      if (_colors!.length == 1) {
        return _colors![0];
      }
      final index = _rand.nextInt(_colors!.length);
      return _colors![index];
    }
    return Helper.randomColor();
  }

  Size _randomSize() {
    return Size(
      Helper.randomize(_minimumSize.width, _maximumSize.width),
      Helper.randomize(_minimumSize.height, _maximumSize.height),
    );
  }
}

typedef GenerateParticleForceCallback = vmath.Vector2 Function();

class Particle {
  Particle(
    Color color,
    Size size,
    this.gravity,
    double particleDrag,
    Path Function(Size size)? createParticlePath, {
    required this.generateParticleForceCallback,
    Size? screenSize,
    Offset? emitterPosition,
  })  : _startUpForce = generateParticleForceCallback(),
        _color = color,
        _mass = Helper.randomize(1, 11),
        _particleDrag = particleDrag,
        _location = vmath.Vector2.zero(),
        _acceleration = vmath.Vector2.zero(),
        _velocity =
            vmath.Vector2(Helper.randomize(-1.5, 1.5), Helper.randomize(-2, 2)),
        _pathShape = createParticlePath != null
            ? createParticlePath(size)
            : createPath(size),
        _aVelocityX = Helper.randomize(-0.1, 0.1) * _zRotationSpeedMultiplier,
        _aVelocityY = Helper.randomize(-0.1, 0.1) * _zRotationSpeedMultiplier,
        _aVelocityZ = Helper.randomize(-0.1, 0.1) * _zRotationSpeedMultiplier,
        _rotateZ = Helper.randomBool(),
        _windSeed = Random().nextDouble() * 1000,
        _baseWindDirection = Random().nextBool() ? 1.0 : -1.0,
        _windIntensity = _generateWindIntensityDistribution(),
        _maxLifetime = _calculateLifetimeBasedOnGravity(gravity),
        _fadeStartRatio = Helper.randomize(0.3, 0.35),
        gravityVector = vmath.Vector2(0, lerpDouble(0.4, 5, gravity)!),
        _screenSize = screenSize ?? Size.zero,
        _active = true;

  final double gravity;

  final vmath.Vector2 _startUpForce;
  final GenerateParticleForceCallback generateParticleForceCallback;

  final vmath.Vector2 _location;
  final vmath.Vector2 _velocity;
  final vmath.Vector2 _acceleration;

  final double _particleDrag;
  double _aX = 0;
  double _aVelocityX;
  double _aY = 0;
  double _aVelocityY;
  double _aZ = 0;
  double _aVelocityZ;
  final vmath.Vector2 gravityVector;
  late final _aAcceleration = 0.0001 / _mass;

  final Color _color;
  final double _mass;
  final Path _pathShape;

  bool _active;

  bool get active => _active;

  final bool _rotateZ;

  double _timeAlive = 0;
  vmath.Vector2 windforceUp = vmath.Vector2(0, -1);

  final double _maxLifetime;
  final double _fadeStartRatio;
  Size
      _screenSize; // Screen size for boundary calculations (non-final to allow updates)

  double _windSeed; // Changed from final to allow pattern changes
  double _baseWindDirection; // Changed from final to allow direction changes
  final double _windIntensity; // Wind intensity for direction changes

  double _lastDirectionChangeTime = 0;
  double _directionChangeInterval = 60;

  static const double _zRotationSpeedMultiplier = 1.5;

  static double _generateWindIntensityDistribution() {
    final random = Random().nextDouble();

    if (random < 0.7) {
      return Helper.randomize(0.3, 0.7);
    } else {
      return Helper.randomize(0.7, 1.0);
    }
  }

  static double _calculateLifetimeBasedOnGravity(double gravity) {
    // Approximation:
    // gravity = 0.0 → lifetime = 420 frames
    // gravity = 1.0 → lifetime = 30 frames
    final baseLifetime = lerpDouble(420, 30, gravity)!;

    // Add a bit of randomness to create diversity
    final minLifetime = baseLifetime * 0.9;
    final maxLifetime = baseLifetime * 1.1;

    return Helper.randomize(minLifetime, maxLifetime);
  }

  static Path createPath(Size size) {
    final pathShape = Path()
      ..moveTo(0, 0)
      ..lineTo(-size.width, 0)
      ..lineTo(-size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // TODO: remove when this is fixed: https://github.com/funwithflutter/flutter_confetti/issues/66
    if (kIsWeb) {
      pathShape
        ..lineTo(-size.width, 0)
        ..lineTo(-size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    }

    return pathShape;
  }

  void reactivate() {
    _timeAlive = 0;

    final f = generateParticleForceCallback();
    _startUpForce.setValues(f.x, f.y);

    _location.setValues(0, 0);
    _acceleration.setValues(0, 0);
    _velocity.setValues(Helper.randomize(-1.5, 1.5), Helper.randomize(-2, 2));

    _aX = 0;
    _aY = 0;
    _aZ = 0;
    _aVelocityX = Helper.randomize(-0.1, 0.1) * _zRotationSpeedMultiplier;
    _aVelocityY = Helper.randomize(-0.1, 0.1) * _zRotationSpeedMultiplier;
    _aVelocityZ = Helper.randomize(-0.2, 0.2) * _zRotationSpeedMultiplier;

    gravityVector.setValues(0, lerpDouble(0.3, 5, gravity)!);

    // Reset direction change properties
    _lastDirectionChangeTime = 0;
    _directionChangeInterval = Helper.randomize(60, 120);

    _active = true;
  }

  void deactivate() {
    _active = false;
  }

  void applyForce(vmath.Vector2 force, double deltaTimeSpeed) {
    final f = force.clone()..divide(vmath.Vector2.all(_mass));
    _acceleration.add(f * deltaTimeSpeed);
  }

  void drag(double deltaTimeSpeed) {
    final speed = sqrt(pow(_velocity.x, 2) + pow(_velocity.y, 2));
    final dragMagnitude = _particleDrag * speed * speed;
    final drag = _velocity.clone()
      ..multiply(vmath.Vector2.all(-1))
      ..normalize()
      ..multiply(vmath.Vector2.all(dragMagnitude));
    applyForce(drag, deltaTimeSpeed);
  }

  void update(double deltaTime) {
    final deltaTimeSpeed = deltaTime * desiredSpeed;
    drag(deltaTimeSpeed);

    if (_timeAlive < 5) {
      applyForce(_startUpForce, deltaTimeSpeed);
    }
    if (_timeAlive < 25) {
      applyForce(windforceUp, deltaTimeSpeed);
      _timeAlive += 1;
    }

    applyForce(gravityVector, deltaTimeSpeed);

    // Check for direction change for high intensity particles
    if (_windIntensity > 0.5 && _timeAlive > 20) {
      _checkDirectionChange();
    }

    final windforceHorizontal = _calculateSmoothWindForce();
    applyForce(windforceHorizontal, deltaTimeSpeed);

    _applyReturnForces(deltaTimeSpeed);

    _velocity.add(_acceleration * deltaTimeSpeed);
    _location.add(_velocity * deltaTimeSpeed);
    _acceleration.setZero();

    _timeAlive += 1;

    _aVelocityX += _aAcceleration;
    _aX += _aVelocityX * deltaTimeSpeed;

    _aVelocityY += _aAcceleration;
    _aY += _aVelocityY * deltaTimeSpeed;

    if (_rotateZ) {
      _aZ += _aVelocityZ * deltaTimeSpeed;
      _aVelocityZ += _aAcceleration * _zRotationSpeedMultiplier;
    }

    // if (_timeAlive >= _maxLifetime) {
    //   deactivate();
    // }
  }

  void _applyReturnForces(double deltaTimeSpeed) {
    if (_screenSize.width <= 0 || _screenSize.height <= 0) {
      return;
    }

    final halfWidth = _screenSize.width * 0.05 + _screenSize.width * 0.5;
    final upwardLimit = -_screenSize.height * 0.05 + _screenSize.height * 0.5;

    if (_location.x < -halfWidth && _velocity.x < 0) {
      final overshootRatio =
          ((-halfWidth - _location.x) / halfWidth).clamp(0.0, 1.5);
      final correctionForce = (0.35 + overshootRatio * 0.9).clamp(0.35, 1.25);
      applyForce(vmath.Vector2(correctionForce, 0), deltaTimeSpeed);
    } else if (_location.x > halfWidth && _velocity.x > 0) {
      final overshootRatio =
          ((_location.x - halfWidth) / halfWidth).clamp(0.0, 1.5);
      final correctionForce = (0.35 + overshootRatio * 0.9).clamp(0.35, 1.25);
      applyForce(vmath.Vector2(-correctionForce, 0), deltaTimeSpeed);
    }

    if (_location.y < upwardLimit && _velocity.y < 0) {
      final overshootRatio =
          ((upwardLimit - _location.y).abs() / (_screenSize.height * 0.45))
              .clamp(0.0, 1.5);
      final correctionForce = (0.45 + overshootRatio * 1.1).clamp(0.45, 1.5);
      applyForce(vmath.Vector2(0, correctionForce), deltaTimeSpeed);
    }
  }

  /// Check if particle should change direction (only for windIntensity > 0.7)
  void _checkDirectionChange() {
    // Check if enough time has passed since last direction change
    if (_timeAlive - _lastDirectionChangeTime >= _directionChangeInterval) {
      // 30% chance to actually change direction each time we check
      if (Random().nextDouble() < 0.3) {
        _performDirectionChange();
        _lastDirectionChangeTime = _timeAlive;

        // Set new random interval for next direction change (1-2 seconds)
        _directionChangeInterval = Helper.randomize(60, 120);
      }
    }
  }

  /// Perform the actual direction change with different types
  void _performDirectionChange() {
    final changeType = Random().nextInt(2);

    switch (changeType) {
      case 0: // Reverse wind direction
        _baseWindDirection *= -1;
        break;

      case 1: // Change oscillation pattern
        _windSeed = Random().nextDouble() * 1000; // New pattern
        break;
    }
  }

  vmath.Vector2 _calculateSmoothWindForce() {
    final timeScale = _timeAlive * 0.2;

    double windForceX = 0;

    if (_windIntensity < 0.7) {
      final slowWave = sin(timeScale + _windSeed) * 0.08;
      final mediumWave = sin(timeScale * 2.0 + _windSeed * 1.2) * 0.06;
      final windVariation = slowWave + mediumWave;

      windForceX = _baseWindDirection * 0.25 * (1 + windVariation);
    } else {
      final slowWave = sin(timeScale + _windSeed) * 0.12;
      final mediumWave = sin(timeScale * 2.5 + _windSeed * 1.3) * 0.10;
      final fastWave = sin(timeScale * 4.0 + _windSeed * 2.1) * 0.05;
      final windVariation = slowWave + mediumWave + fastWave;

      windForceX =
          _baseWindDirection * _windIntensity * 0.35 * (1 + windVariation);
    }
    final windForceY = sin(timeScale * 2.0 + _windSeed) * 0.03;
    return vmath.Vector2(windForceX, windForceY);
  }

  /// Update screen size for boundary calculations
  void _updateScreenSize(Size newSize) {
    _screenSize = newSize;
  }

  Offset get location {
    if (_location.x.isNaN || _location.y.isNaN) {
      return const Offset(0, 0);
    }
    return Offset(_location.x, _location.y);
  }

  Color get color {
    final opacity = _calculateOpacity();
    return _color.withOpacity(opacity);
  }

  Color get originalColor => _color;

  double _calculateOpacity() {
    final fadeStartTime = _maxLifetime * _fadeStartRatio;
    if (_timeAlive <= fadeStartTime) {
      return 1.0;
    }

    if (_timeAlive >= _maxLifetime) {
      return 0.0;
    }

    // Calculate opacity fading from fadeStartTime to maxLifetime
    final fadeProgress =
        (_timeAlive - fadeStartTime) / (_maxLifetime - fadeStartTime);
    final opacity = 1.0 - fadeProgress;

    return opacity.clamp(0.01, 1.0);
  }

  Path get path => _pathShape;

  double get angleX => _aX;

  double get angleY => _aY;

  double get angleZ => _aZ;

  bool get rotateZ => _rotateZ;
}
