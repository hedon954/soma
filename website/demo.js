const goals = document.querySelectorAll('input[name="goal"]');
const variants = document.querySelectorAll('[data-goal]');
const motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
const entranceCurve = 'cubic-bezier(0.23, 1, 0.32, 1)';
let activeAnimations = [];

function cancelPlayback() {
  for (const animation of activeAnimations) animation.cancel();
  activeAnimations = [];
}

function playConversation(panel) {
  cancelPlayback();
  if (motionPreference.matches || !panel.animate) return;

  activeAnimations = Array.from(panel.children, (part, index) => part.animate(
    [
      { opacity: 0, transform: 'translateY(7px)' },
      { opacity: 1, transform: 'translateY(0)' },
    ],
    { duration: 220, delay: index * 200, easing: entranceCurve, fill: 'backwards' },
  ));
}

const firstPanel = document.querySelector('.goal-dialogue');
const intro = new IntersectionObserver(([entry], observer) => {
  if (!entry.isIntersecting || entry.intersectionRatio < .25) return;
  observer.disconnect();
  playConversation(firstPanel);
}, { threshold: .25 });
intro.observe(firstPanel);
motionPreference.addEventListener('change', cancelPlayback);

for (const goal of goals) {
  goal.addEventListener('change', () => {
    intro.disconnect();
    for (const section of variants) section.hidden = section.dataset.goal !== goal.value;
    const panel = document.getElementById(goal.getAttribute('aria-controls'));
    if (goal.matches(':focus-visible')) cancelPlayback();
    else playConversation(panel);
  });
}
