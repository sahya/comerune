(function () {
  // 隠しベータ: ロゴを通算5回クリックで開錠。期限後は不可（クライアント時計依存のソフトゲート）。
  var DEADLINE_MS = new Date('2026-05-25T00:00:00+09:00').getTime(); // 2026-05-24 まで
  var REQUIRED_CLICKS = 5;

  var logo = document.querySelector('.hero .logo');
  var section = document.getElementById('beta');
  if (!logo || !section) return;

  var count = 0;

  logo.addEventListener('click', function () {
    if (!(Date.now() < DEADLINE_MS)) return; // 期限切れ／不正日時は開錠しない
    if (++count < REQUIRED_CLICKS) return;
    if (section.hidden) {
      section.hidden = false;
      section.scrollIntoView({ behavior: 'smooth', block: 'start' });
      section.focus({ preventScroll: true });
    }
  });
})();
