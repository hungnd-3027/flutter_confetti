const double kLowLimit = 1 / 60;
const desiredSpeed = (1 / kLowLimit) * 0.80; // Giảm 20% tốc độ

// Time-based constants for consistent opacity/lifetime  
const double kParticleLifetimeSeconds = 7.0; // Always 7 seconds regardless of framerate
