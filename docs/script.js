/* ========================================
   Strid — Interactive Documentation
   Terminal animation, scroll reveal,
   chart animations, FAQ accordion
   ======================================== */

// --- Hero Terminal Animation ---
(function initTerminal() {
  var body = document.getElementById('terminal-body');
  if (!body) return;

  var lines = [
    { type: 'cmd', text: 'strid detect bank_statement.txt -c' },
    { type: 'blank' },
    { type: 'header', text: '        PII Summary' },
    { type: 'divider' },
    { type: 'row', entity: 'IN_TXN_REF', count: '1464' },
    { type: 'row', entity: 'IN_UPI_ID', count: '650' },
    { type: 'row', entity: 'IN_PHONE', count: '540' },
    { type: 'row', entity: 'IN_IFSC', count: '430' },
    { type: 'row', entity: 'LOCATION', count: '147' },
    { type: 'row', entity: 'PERSON', count: '101' },
    { type: 'row', entity: 'IN_BANK_ACCOUNT', count: '51' },
    { type: 'row', entity: 'EMAIL_ADDRESS', count: '50' },
    { type: 'row', entity: 'IN_PAN', count: '1' },
    { type: 'divider' },
    { type: 'total', text: '  Total: 4089 entities' },
    { type: 'blank' },
    { type: 'cmd', text: 'strid redact bank_statement.txt -o clean.txt' },
    { type: 'success', text: 'Redacted output written to clean.txt' },
    { type: 'blank' },
    { type: 'cmd', text: 'head -5 clean.txt' },
    { type: 'output', text: 'HDFC BANK Ltd.              Page No.: 1' },
    { type: 'output', text: '' },
    { type: 'output', text: '  Account Branch : <IN_BRANCH_CODE>' },
    { type: 'output', text: '  Email          : <EMAIL_ADDRESS>' },
    { type: 'output', text: '  Account No     : <IN_BANK_ACCOUNT>' },
    { type: 'blank' },
    { type: 'success', text: 'All PII redacted. Transaction dates preserved.' },
  ];

  var lineIndex = 0;
  body.innerHTML = '';

  function addLine() {
    if (lineIndex >= lines.length) return;

    var line = lines[lineIndex];
    var el = document.createElement('div');
    el.className = 'terminal-line';

    switch (line.type) {
      case 'cmd':
        el.innerHTML = '<span class="terminal-prompt">$</span> ' + line.text;
        break;
      case 'blank':
        el.innerHTML = '&nbsp;';
        break;
      case 'header':
        el.innerHTML = '<span class="terminal-entity">' + line.text + '</span>';
        break;
      case 'divider':
        el.innerHTML = '<span class="terminal-dim">  ┏━━━━━━━━━━━━━━━━━━┳━━━━━━━┓</span>';
        break;
      case 'row':
        var padded = (line.entity + '                  ').slice(0, 18);
        var count = ('     ' + line.count).slice(-5);
        el.innerHTML = '<span class="terminal-dim">  ┃</span> <span class="terminal-entity">' + padded + '</span><span class="terminal-dim">┃</span> <span class="terminal-score">' + count + '</span> <span class="terminal-dim">┃</span>';
        break;
      case 'total':
        el.innerHTML = '<span class="terminal-success">' + line.text + '</span>';
        break;
      case 'success':
        el.innerHTML = '<span class="terminal-success">  ✔ ' + line.text + '</span>';
        break;
      case 'output':
        el.innerHTML = '<span class="terminal-dim">  ' + escapeHtml(line.text) + '</span>';
        break;
    }

    body.appendChild(el);
    body.scrollTop = body.scrollHeight;
    lineIndex++;

    var delay = line.type === 'cmd' ? 600 : line.type === 'blank' ? 200 : 120;
    setTimeout(addLine, delay);
  }

  function escapeHtml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // Start after a short delay
  setTimeout(addLine, 800);
})();


// --- FAQ Accordion ---
(function initFaq() {
  var items = document.querySelectorAll('.faq-item');
  items.forEach(function (item) {
    var q = item.querySelector('.faq-q');
    if (!q) return;

    q.addEventListener('click', function () {
      var wasOpen = item.classList.contains('open');

      var category = item.closest('.faq-category');
      if (category) {
        category.querySelectorAll('.faq-item.open').forEach(function (openItem) {
          openItem.classList.remove('open');
        });
      }

      if (!wasOpen) {
        item.classList.add('open');
      }
    });

    q.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        q.click();
      }
    });
  });
})();


// --- Scroll Reveal ---
(function initScrollReveal() {
  var sections = document.querySelectorAll('section');

  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
      }
    });
  }, {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
  });

  sections.forEach(function (section) {
    observer.observe(section);
  });
})();


// --- Bar Chart Animation ---
(function initBarChart() {
  var chart = document.getElementById('stats-chart');
  if (!chart) return;

  var fills = chart.querySelectorAll('.bc-fill');
  var originalWidths = [];

  fills.forEach(function (fill) {
    originalWidths.push(fill.style.width);
    fill.style.width = '0%';
  });

  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        fills.forEach(function (fill, i) {
          setTimeout(function () {
            fill.style.width = originalWidths[i];
          }, i * 80);
        });
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.2 });

  observer.observe(chart);
})();


// --- Cards Grid Stagger Animation ---
(function initCardsAnimation() {
  var grid = document.getElementById('entities-grid');
  if (!grid) return;

  var cards = grid.querySelectorAll('.card');

  cards.forEach(function (card) {
    card.style.opacity = '0';
    card.style.transform = 'translateY(15px)';
    card.style.transition = 'opacity 0.4s ease, transform 0.4s ease';
  });

  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        cards.forEach(function (card, i) {
          setTimeout(function () {
            card.style.opacity = '1';
            card.style.transform = 'translateY(0)';
          }, i * 60);
        });
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.15 });

  observer.observe(grid);
})();


// --- Scroll Indicator ---
(function initScrollIndicator() {
  var indicator = document.querySelector('.scroll-indicator');
  if (!indicator) return;

  indicator.style.cursor = 'pointer';
  indicator.addEventListener('click', function () {
    var firstSection = document.querySelector('section');
    if (firstSection) {
      firstSection.scrollIntoView({ behavior: 'smooth' });
    }
  });

  window.addEventListener('scroll', function () {
    var scrollY = window.scrollY || window.pageYOffset;
    indicator.style.opacity = Math.max(0, 1 - scrollY / 300);
  }, { passive: true });
})();
