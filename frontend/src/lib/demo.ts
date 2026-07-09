/**
 * PUBLIC demo questions & answers — INTENTIONALLY INSECURE.
 *
 * The answers are published here on purpose so the demo is fully reproducible: anyone can clone
 * the repo, run the frontend, type these answers and drive the shared demo account. In a real
 * deployment each user would choose SECRET, high-entropy answers at setup time (SETUP screen),
 * and would never commit them. See the README "Security model" section.
 */
export const DEMO_QUESTIONS: readonly string[] = [
  'What was the name of your first pet?',
  'In which city were you born?',
  'What is your favorite movie?',
];

/** The matching PUBLIC answers (insecure on purpose). */
export const DEMO_ANSWERS: readonly string[] = ['rex', 'paris', 'inception'];
