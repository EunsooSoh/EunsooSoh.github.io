---
layout: page
title: 빈 칸 퀴즈
icon: fas fa-pen
order: 5
---

포스트를 고르고 빈 칸 방식을 선택하세요.

- 기본: 본문의 굵은 글씨
- 지정: 
  - **편집 모드**에서 본문을 드래그하면 그 부분이 빈 칸이 되고, 빈 칸을 클릭하면 취소
  - **풀이 모드**로 바꿔 채워 넣고 **확인**

<div id="quiz-controls" class="d-flex flex-wrap align-items-center mb-3" style="gap:.5rem">
  <select id="quiz-cat" class="form-select" style="max-width:100%;width:auto">
    <option value="">전체 카테고리</option>
  </select>
  <select id="quiz-post" class="form-select" style="max-width:100%;width:auto;min-width:16rem">
    <option value="">포스트 선택…</option>
    {% for post in site.posts %}
    <option value="{{ post.url | relative_url }}" data-cat="{{ post.categories | join: ' / ' | escape }}">{{ post.date | date: "%Y-%m-%d" }} · {{ post.title | escape }}</option>
    {% endfor %}
  </select>
  <label class="mb-0">방식
    <select id="quiz-mode">
      <option value="bold">굵은 글씨 자동</option>
      <option value="manual">직접 지정</option>
    </select>
  </label>
  <label class="mb-0" id="quiz-ratio-wrap">빈 칸 비율
    <select id="quiz-ratio">
      <option value="1">전부</option>
      <option value="0.7">70%</option>
      <option value="0.5">50%</option>
      <option value="0.3">30%</option>
    </select>
  </label>
  <button id="quiz-start" type="button" class="btn btn-outline-primary btn-sm">퀴즈 생성</button>
</div>

<div id="quiz-bar" class="mb-3" style="display:none;position:sticky;top:0;z-index:5;padding:.5rem 0;background:var(--main-bg)">
  <button id="quiz-edit" type="button" class="btn btn-outline-primary btn-sm" style="display:none">편집 모드로</button>
  <button id="quiz-clearall" type="button" class="btn btn-outline-danger btn-sm" style="display:none">빈 칸 모두 지우기</button>
  <button id="quiz-check" type="button" class="btn btn-primary btn-sm">확인</button>
  <button id="quiz-reveal" type="button" class="btn btn-outline-secondary btn-sm">정답 보기</button>
  <button id="quiz-reset" type="button" class="btn btn-outline-secondary btn-sm">초기화</button>
  <span id="quiz-score" style="margin-left:.75rem"></span>
</div>

<div id="quiz-body" class="content"></div>

<style>
  #quiz-body input.blank {
    border: 0; border-bottom: 2px solid var(--link-color, #2a6df4);
    background: transparent; color: inherit; text-align: center;
    padding: 0 .2rem; margin: 0 .1rem; outline: none; border-radius: 0;
  }
  #quiz-body input.blank:focus { background: rgba(42,109,244,.08); }
  #quiz-body input.blank.ok { border-color: #2e9d57; background: rgba(46,157,87,.12); }
  #quiz-body input.blank.no { border-color: #d64545; background: rgba(214,69,69,.12); }
  #quiz-body input.blank.shown { border-color: #b8860b; background: rgba(184,134,11,.12); }
  #quiz-body span.mark { background: rgba(255,200,0,.35); border-bottom: 2px solid #e0a800; cursor: pointer; }
  #quiz-body span.mark:hover { background: rgba(214,69,69,.25); text-decoration: line-through; }
</style>

<script>
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var sel = $('quiz-post'), modeSel = $('quiz-mode'), ratio = $('quiz-ratio');
  var body = $('quiz-body'), bar = $('quiz-bar'), score = $('quiz-score');
  var editBtn = $('quiz-edit'), clearBtn = $('quiz-clearall'), ratioWrap = $('quiz-ratio-wrap');

  var pristine = null;
  var ranges = [];
  var editing = true;
  var blanks = [];
  var notice = '';

  function storeKey() { return 'quiz-ranges:' + sel.value; }
  function saveRanges() { localStorage.setItem(storeKey(), JSON.stringify(ranges)); }
  function loadRanges() {
    try { ranges = JSON.parse(localStorage.getItem(storeKey())) || []; } catch (e) { ranges = []; }
  }

  function norm(s) { return s.toLowerCase().replace(/[\s .,:;!?'"`*_\-]/g, ''); }

  function answers(text) {
    var set = {}, t = text.trim();
    function add(x) { x = norm(x); if (x) set[x] = true; }
    add(t);
    var m = t.match(/^(.*?)\s*[(（](.*)[)）]\s*$/);
    if (m) { add(m[1]); add(m[2]); }
    t.split(/\s*\/\s*/).forEach(add);
    return Object.keys(set);
  }

  function reconcile() {
    var nodes = textNodes(pristine);
    var full = nodes.map(function (t) { return t.node.nodeValue; }).join('');
    function fits(s, e) {
      return nodes.some(function (t) { return s >= t.start && e <= t.start + t.node.nodeValue.length; });
    }
    function overlaps(s, e, list) {
      return list.some(function (r) { return s < r.e && e > r.s; });
    }
    var kept = [], dropped = 0, moved = 0;
    ranges.slice().sort(function (a, b) { return a.s - b.s; }).forEach(function (r) {
      if (!r.text) {
        if (r.e <= full.length && fits(r.s, r.e) && !overlaps(r.s, r.e, kept)) {
          kept.push({ s: r.s, e: r.e, text: full.slice(r.s, r.e) });
        } else dropped++;
        return;
      }
      if (full.slice(r.s, r.e) === r.text && fits(r.s, r.e) && !overlaps(r.s, r.e, kept)) {
        kept.push(r);
        return;
      }
      var best = -1, i = full.indexOf(r.text);
      while (i !== -1) {
        var j = i + r.text.length;
        if (fits(i, j) && !overlaps(i, j, kept) && (best === -1 || Math.abs(i - r.s) < Math.abs(best - r.s))) best = i;
        i = full.indexOf(r.text, i + 1);
      }
      if (best === -1) { dropped++; return; }
      kept.push({ s: best, e: best + r.text.length, text: r.text });
      moved++;
    });
    var changed = dropped > 0 || moved > 0 || kept.length !== ranges.length;
    ranges = kept;
    if (changed) saveRanges();
    notice = dropped ? '⚠ 본문이 바뀌어 빈 칸 ' + dropped + '개가 제외됐어요.' : '';
  }

  function makeInput(answer) {
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'blank';
    input.autocomplete = 'off';
    input.spellcheck = false;
    input.size = Math.max(4, Math.min(answer.length + 1, 32));
    input.dataset.answer = answer;
    input.setAttribute('aria-label', '빈 칸');
    blanks.push(input);
    return input;
  }

  function textNodes(root) {
    var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        return n.parentNode.closest('script,style') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      }
    });
    var list = [], pos = 0, n;
    while ((n = w.nextNode())) { list.push({ node: n, start: pos }); pos += n.nodeValue.length; }
    return list;
  }

  function renderBold(root) {
    var p = parseFloat(ratio.value);
    var targets = [];
    root.querySelectorAll('strong, b').forEach(function (el) {
      if (el.closest('h1,h2,h3,h4,h5,h6,pre,table')) return;
      var text = el.textContent.trim();
      if (text.length < 2 || text.length > 40) return;
      if (Math.random() > p) return;
      targets.push([el, text]);
    });
    targets.forEach(function (t) { t[0].replaceWith(makeInput(t[1])); });
  }

  function renderManual(root) {
    var nodes = textNodes(root);
    ranges.slice().sort(function (a, b) { return b.s - a.s; }).forEach(function (r) {
      for (var i = 0; i < nodes.length; i++) {
        var t = nodes[i], len = t.node.nodeValue.length;
        if (r.s >= t.start && r.e <= t.start + len) {
          var rg = document.createRange();
          rg.setStart(t.node, r.s - t.start);
          rg.setEnd(t.node, r.e - t.start);
          var answer = rg.toString();
          var holder;
          if (editing) {
            holder = document.createElement('span');
            holder.className = 'mark';
            holder.dataset.s = r.s;
            holder.title = '클릭하면 빈 칸 취소';
            rg.surroundContents(holder);
          } else {
            rg.deleteContents();
            rg.insertNode(makeInput(answer));
          }
          return;
        }
      }
    });
    blanks.reverse();
  }

  function render() {
    blanks = [];
    body.innerHTML = '';
    if (!pristine) return;
    var root = pristine.cloneNode(true);
    var manual = modeSel.value === 'manual';
    ratioWrap.style.display = manual ? 'none' : '';
    editBtn.style.display = clearBtn.style.display = manual ? '' : 'none';
    $('quiz-check').style.display = $('quiz-reveal').style.display = $('quiz-reset').style.display =
      (manual && editing) ? 'none' : '';

    if (manual) {
      renderManual(root);
      editBtn.textContent = editing ? '풀이 모드로' : '편집 모드로';
    } else {
      renderBold(root);
    }
    body.appendChild(root);
    bar.style.display = '';

    if (manual && editing) {
      score.textContent = '직접 생성한 빈 칸 (현재 ' + ranges.length + '개)';
    } else if (blanks.length) {
      score.textContent = '빈 칸 ' + blanks.length + '개';
    } else {
      score.textContent = manual ? '빈 칸 없음'
                                 : '포스트에 굵은 글씨가 없음';
    }
    if (notice) score.textContent = notice + ' ' + score.textContent;
    if (window.MathJax && MathJax.typesetPromise) MathJax.typesetPromise([body]);
  }

  function load(keepRanges) {
    if (!sel.value) return;
    body.textContent = '불러오는 중…';
    fetch(sel.value)
      .then(function (r) { return r.text(); })
      .then(function (html) {
        var content = new DOMParser().parseFromString(html, 'text/html').querySelector('.content');
        if (!content) { body.textContent = '본문을 찾지 못함'; return; }
        pristine = content.cloneNode(true);
        pristine.querySelectorAll('.anchor, .post-meta, script').forEach(function (n) { n.remove(); });
        pristine.querySelectorAll('mjx-container').forEach(function (n) { /* 렌더 전 원본이라 보통 없음 */ });
        notice = '';
        if (!keepRanges) { loadRanges(); reconcile(); }
        editing = ranges.length === 0;
        render();
      })
      .catch(function () { body.textContent = '불러오지 못함'; });
  }

  function onSelect() {
    if (modeSel.value !== 'manual' || !editing) return;
    var s = window.getSelection();
    if (!s || s.isCollapsed || !s.rangeCount) return;
    var r = s.getRangeAt(0);
    if (r.startContainer !== r.endContainer || r.startContainer.nodeType !== 3 || !body.contains(r.startContainer)) {
      score.textContent = '한 덩어리의 글(굵게/코드/기존 빈 칸 경계를 넘지 않는 범위)만 선택 가능';
      return;
    }
    var text = r.toString();
    var lead = text.length - text.replace(/^\s+/, '').length;
    var trail = text.length - text.replace(/\s+$/, '').length;
    var start = r.startOffset + lead, end = r.endOffset - trail;
    if (end <= start) return;
    var base = 0, found = false;
    textNodes(body).forEach(function (t) { if (t.node === r.startContainer) { base = t.start; found = true; } });
    if (!found) return;
    ranges.push({ s: base + start, e: base + end, text: r.toString().trim() });
    saveRanges();
    s.removeAllRanges();
    render();
  }
  body.addEventListener('mouseup', function () { setTimeout(onSelect, 0); });
  body.addEventListener('touchend', function () { setTimeout(onSelect, 300); });

  body.addEventListener('click', function (e) {
    var m = e.target.closest && e.target.closest('span.mark');
    if (!m || !editing) return;
    var s = parseInt(m.dataset.s, 10);
    ranges = ranges.filter(function (r) { return r.s !== s; });
    saveRanges();
    render();
  });

  editBtn.onclick = function () {
    if (editing && ranges.length === 0) { score.textContent = '빈 칸을 하나 이상 지정'; return; }
    editing = !editing;
    render();
  };
  clearBtn.onclick = function () {
    if (!ranges.length || !confirm('지정한 빈 칸을 모두 지울까요?')) return;
    ranges = []; saveRanges(); editing = true; render();
  };

  function clear(i) { i.classList.remove('ok', 'no', 'shown'); }

  $('quiz-check').onclick = function () {
    var ok = 0;
    blanks.forEach(function (i) {
      clear(i);
      var good = answers(i.dataset.answer).indexOf(norm(i.value)) !== -1 && norm(i.value) !== '';
      i.classList.add(good ? 'ok' : 'no');
      if (good) ok++;
    });
    score.textContent = ok + ' / ' + blanks.length + ' 정답';
  };
  $('quiz-reveal').onclick = function () {
    blanks.forEach(function (i) {
      if (!i.classList.contains('ok')) {
        clear(i); i.value = i.dataset.answer; i.classList.add('shown');
        i.size = Math.max(i.size, Math.min(i.value.length + 1, 40));
      }
    });
  };
  $('quiz-reset').onclick = function () {
    blanks.forEach(function (i) { clear(i); i.value = ''; });
    score.textContent = '빈 칸 ' + blanks.length + '개';
  };

  $('quiz-start').onclick = function () {
    if (pristine && sel.value) { editing = modeSel.value === 'manual' && ranges.length === 0; render(); } else load();
  };
  var catSel = $('quiz-cat');
  var allOpts = Array.prototype.slice.call(sel.options, 1);
  var cats = [];
  allOpts.forEach(function (o) {
    var c = o.getAttribute('data-cat');
    if (c && cats.indexOf(c) < 0) cats.push(c);
  });
  cats.sort().forEach(function (c) {
    var o = document.createElement('option');
    o.value = c; o.textContent = c;
    catSel.appendChild(o);
  });
  catSel.onchange = function () {
    var cur = sel.value;
    while (sel.options.length > 1) sel.remove(1);
    allOpts.forEach(function (o) {
      if (!catSel.value || o.getAttribute('data-cat') === catSel.value) sel.appendChild(o);
    });
    if (cur !== sel.value) { sel.value = ''; pristine = null; load(false); }
  };
  sel.onchange = function () { pristine = null; load(false); };
  modeSel.onchange = function () { if (pristine) { editing = ranges.length === 0; render(); } };
  body.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' || !e.target.classList.contains('blank')) return;
    var n = blanks[blanks.indexOf(e.target) + 1];
    if (n) n.focus(); else $('quiz-check').click();
  });
})();
</script>
