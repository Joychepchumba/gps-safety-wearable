#pragma once
#include <stdint.h>
// Two-detection trigger: call update() once per inference with the best keyword score (max over keyword classes).
// Returns true exactly when an alert should START (then run your cancel window before sending anything).
struct KwsTrigger {
  float threshold; int64_t pair_window_ms, refractory_ms, cooldown_ms;
  int64_t last_det_ms = -1000000000LL, prev_event_ms = -1000000000LL, last_alert_ms = -1000000000LL;
  KwsTrigger(float thr, int64_t pair, int64_t refr, int64_t cool)
      : threshold(thr), pair_window_ms(pair), refractory_ms(refr), cooldown_ms(cool) {}
  bool update(int64_t now_ms, float best_keyword_score) {
    if (best_keyword_score < threshold) return false;
    bool new_event = (now_ms - last_det_ms) >= refractory_ms;
    last_det_ms = now_ms;
    if (!new_event) return false;
    bool alert = (now_ms - prev_event_ms) <= pair_window_ms && (now_ms - last_alert_ms) >= cooldown_ms;
    prev_event_ms = now_ms;
    if (alert) last_alert_ms = now_ms;
    return alert;
  }
};
