import { AppConstants } from '../common/constants/AppConstants';

export class WebScrapeService {
  static buildCourseTableScrapeScript(): string {
    return `
      (function() {
        try {
          var data = null;
          var unitCountValue = 0;

          if (typeof table0 !== 'undefined' && table0) {
            data = table0;
          } else if (window.table0) {
            data = window.table0;
          } else if (document.defaultView && document.defaultView.table0) {
            data = document.defaultView.table0;
          }

          if (typeof unitCount !== 'undefined') {
            unitCountValue = unitCount;
          } else if (window.unitCount) {
            unitCountValue = window.unitCount;
          }

          if (data && data.activities) {
            var jsonStr = JSON.stringify({
              unitCounts: unitCountValue || 12,
              activities: data.activities,
              source: 'direct'
            });
            try {
              return btoa(unescape(encodeURIComponent(jsonStr)));
            } catch (e) {
              return JSON.stringify({ error: 'base64编码失败', raw: jsonStr.substring(0, 200) });
            }
          }

          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              var iframeWin = iframes[i].contentWindow;
              if (iframeWin && iframeWin.table0) {
                var iframeJsonStr = JSON.stringify({
                  unitCounts: iframeWin.unitCount || 12,
                  activities: iframeWin.table0.activities || [],
                  source: 'iframe'
                });
                try {
                  return btoa(unescape(encodeURIComponent(iframeJsonStr)));
                } catch (e) {
                  return JSON.stringify({ error: 'iframe base64编码失败' });
                }
              }
            } catch (e) {}
          }

          return JSON.stringify({ error: '未找到table0', tablesCount: document.querySelectorAll('table').length });
        } catch (e) {
          return JSON.stringify({ error: e.message });
        }
      })()
    `;
  }

  static buildExamScrapeScript(): string {
    return `
      (function() {
        try {
          var formTableRows = document.querySelectorAll('table.formTable tr');
          var examsRows = document.querySelectorAll('#exams tbody tr');
          var candidateRows = [];
          for (var i = 0; i < formTableRows.length; i++) {
            candidateRows.push(formTableRows[i]);
          }
          for (var j = 0; j < examsRows.length; j++) {
            candidateRows.push(examsRows[j]);
          }

          var exams = [];
          var UNKNOWN = '未知';
          function cellText(cells, idx) {
            if (idx < cells.length) {
              var t = (cells[idx].innerText || '').trim();
              return t || UNKNOWN;
            }
            return UNKNOWN;
          }
          for (var k = 0; k < candidateRows.length; k++) {
            var cells = candidateRows[k].querySelectorAll('td');
            if (!cells || cells.length < 3) {
              continue;
            }
            var c2 = (cells[1].innerText || '').trim();
            var c3 = (cells[2].innerText || '').trim();
            if (!c2 || c2 === '课程名称' || !c3) {
              continue;
            }
            exams.push({
              courseNo: cellText(cells, 0),
              courseName: c2,
              examDate: c3,
              examTimeRange: cellText(cells, 3),
              examLocation: cellText(cells, 4),
              seatNo: cellText(cells, 5),
              examStatus: cellText(cells, 6),
              examType: cellText(cells, 7),
              remark: cellText(cells, 8)
            });
          }

          var diagnostics = {
            currentUrl: window.location.href || '',
            formTableRowCount: formTableRows.length,
            examsTableRowCount: examsRows.length,
            totalCandidateRows: candidateRows.length,
            parsedExamCount: exams.length,
            hasSemesterInput: !!document.querySelector('input[name="semester.id"]'),
            hasExamTypeInput: !!document.querySelector('input[name="examType.id"]'),
            sampleCellText: (document.querySelector('table.formTable td') && document.querySelector('table.formTable td').innerText) ? document.querySelector('table.formTable td').innerText.trim() : ''
          };

          return JSON.stringify({ exams: exams, diagnostics: diagnostics });
        } catch (e) {
          return JSON.stringify({
            exams: [],
            diagnostics: {
              currentUrl: window.location.href || '',
              formTableRowCount: 0,
              examsTableRowCount: 0,
              totalCandidateRows: 0,
              parsedExamCount: 0,
              hasSemesterInput: false,
              hasExamTypeInput: false,
              sampleCellText: ''
            },
            error: e && e.message ? e.message : 'unknown error'
          });
        }
      })()
    `;
  }

  static buildLoginCheckScript(): string {
    return `
      (function() {
        try {
          var currentUrl = window.location.href || '';

          // 1. 登录页面判定（统一身份认证 / CAS / IDAS 或页面含登录输入框）
          if (currentUrl.includes('authserver/login') || currentUrl.includes('idas.uestc.edu.cn') ||
              document.querySelector('input[type="password"]') || document.querySelector('#username') ||
              document.querySelector('input[name="username"]')) {
            return JSON.stringify({ status: 'not_logged_in', reason: 'on_login_page' });
          }

          var bodyText = document.body ? (document.body.innerText || '') : '';
          var htmlText = document.documentElement ? (document.documentElement.innerHTML || '') : '';

          // 2. 检查是否为多账号/重复登录踢出确认页 (home.action)
          if (htmlText.includes('重复登录') || htmlText.includes('已将之前的登录踢出') ||
              (currentUrl.includes('home.action') && (bodyText.includes('点击此处') || htmlText.includes('点击此处')))) {
            var links = document.querySelectorAll('a');
            var targetHref = 'https://eams.uestc.edu.cn/eams/home.action';
            for (var i = 0; i < links.length; i++) {
              var t = (links[i].innerText || '').trim();
              var h = links[i].getAttribute('href') || '';
              if (t.includes('点击此处') || h.includes('home.action')) {
                targetHref = links[i].href || targetHref;
                break;
              }
            }
            if (targetHref.indexOf('http://') === 0 && targetHref.indexOf('http://webvpn') !== 0) {
              targetHref = 'https://' + targetHref.substring(7);
            }
            return JSON.stringify({ status: 'repeat_login_prompt', href: targetHref });
          }

          // 3. 已登录页面判定：在教务系统/WebVPN域名下且已非登录/踢出页
          if (currentUrl.includes('eams.uestc.edu.cn') || currentUrl.includes('webvpn.uestc.edu.cn')) {
            return JSON.stringify({ status: 'logged_in', reason: 'eams_authenticated' });
          }

          return JSON.stringify({ status: 'unknown', url: currentUrl });
        } catch (e) {
          return JSON.stringify({ status: 'error', error: e.message });
        }
      })()
    `;
  }

  static buildConfirmRepeatLoginScript(): string {
    return `
      (function() {
        try {
          var links = document.querySelectorAll('a');
          for (var i = 0; i < links.length; i++) {
            var t = (links[i].innerText || '').trim();
            var h = links[i].getAttribute('href') || '';
            if (t.includes('点击此处') || h.includes('home.action')) {
              var targetHref = links[i].href || 'https://eams.uestc.edu.cn/eams/home.action';
              if (targetHref.indexOf('http://') === 0 && targetHref.indexOf('http://webvpn') !== 0) {
                targetHref = 'https://' + targetHref.substring(7);
              }
              window.location.replace(targetHref);
              return JSON.stringify({ success: true, method: 'navigated', href: targetHref });
            }
          }
          window.location.replace('https://eams.uestc.edu.cn/eams/home.action');
          return JSON.stringify({ success: true, method: 'navigated_fallback' });
        } catch (e) {
          return JSON.stringify({ success: false, error: e.message });
        }
      })()
    `;
  }

  static buildFindCourseTableLinkScript(): string {
    return `
      (function() {
        try {
          var links = document.querySelectorAll('a');
          for (var i = 0; i < links.length; i++) {
            var href = links[i].getAttribute('href') || '';
            if (href.includes('courseTableForStd')) {
              return JSON.stringify({ type: 'navigate', href: links[i].href });
            }
          }

          var titleLinks = document.querySelectorAll('a[mytitle*="课表"]');
          if (titleLinks.length > 0) {
            return JSON.stringify({ type: 'navigate', href: titleLinks[0].href });
          }

          var enLinks = document.querySelectorAll('a[enname*="Course Table"]');
          if (enLinks.length > 0) {
            return JSON.stringify({ type: 'navigate', href: enLinks[0].href });
          }

          var childMenuLinks = document.querySelectorAll('a.childMenu');
          for (var j = 0; j < childMenuLinks.length; j++) {
            var childHref = childMenuLinks[j].getAttribute('href') || '';
            if (childHref.includes('courseTable')) {
              return JSON.stringify({ type: 'navigate', href: childMenuLinks[j].href });
            }
          }

          var currentHost = window.location.host;
          if (currentHost.includes('eams.uestc.edu.cn')) {
            var courseTableUrl = '${AppConstants.EAMS_COURSE_TABLE_URL}';
            return JSON.stringify({ type: 'navigate', href: courseTableUrl });
          }

          return JSON.stringify({ error: '未找到课表链接' });
        } catch (e) {
          return JSON.stringify({ error: e.message });
        }
      })()
    `;
  }

  static buildGradeScrapeScript(): string {
    return `
(function() {
  try {
    var allDocs = [document];
    var iframes = document.querySelectorAll('iframe, frame');
    for (var f = 0; f < iframes.length; f++) {
      try {
        var doc = iframes[f].contentDocument || (iframes[f].contentWindow ? iframes[f].contentWindow.document : null);
        if (doc) {
          allDocs.push(doc);
        }
      } catch (fe) {}
    }

    var resultTable = null;
    var resultName = '';

    for (var d = 0; d < allDocs.length; d++) {
      var currentDoc = allDocs[d];
      var gridtable = currentDoc.querySelector('.gridtable');
      if (gridtable) { resultTable = gridtable; resultName = '.gridtable (doc ' + d + ')'; break; }
      var gt2 = currentDoc.querySelector('#grid10066233341') || currentDoc.querySelector('#grid18466436161');
      if (gt2) { resultTable = gt2; resultName = 'gridId (doc ' + d + ')'; break; }

      var allTables = currentDoc.querySelectorAll('table');
      for (var ti = 0; ti < allTables.length; ti++) {
        var t = allTables[ti];
        var html = (t.innerHTML || '').toLowerCase();
        if (html.indexOf('学分') >= 0 || html.indexOf('成绩') >= 0 || html.indexOf('绩点') >= 0 ||
            html.indexOf('credit') >= 0 || html.indexOf('score') >= 0 || html.indexOf('course') >= 0) {
          resultTable = t;
          resultName = 'table[' + ti + '] (keyword match doc ' + d + ')';
          break;
        }
      }
      if (resultTable) break;
    }

    if (!resultTable) {
      return JSON.stringify({
        grades: [],
        diagnostics: {
          currentUrl: window.location.href,
          pageTitle: document.title || '',
          rowCount: 0,
          parsedCount: 0,
          sampleRow: 'no table found',
          allTablesOnPage: document.querySelectorAll('table').length,
          iframeCount: iframes.length,
          bodySnippet: (document.body ? (document.body.innerText || '') : '').substring(0, 300)
        },
        error: '未找到成绩表格'
      });
    }

    var tbody = resultTable.querySelector('tbody');
    var rows;
    if (tbody) {
      rows = tbody.querySelectorAll('tr');
    } else {
      rows = resultTable.querySelectorAll('tr');
    }

    var grades = [];
    for (var i = 0; i < rows.length; i++) {
      var cells = rows[i].querySelectorAll('td');
      var ths = rows[i].querySelectorAll('th');
      if (cells.length < 2 && ths.length > 0) { continue; }
      if (cells.length < 2) { continue; }

      var courseName = ((cells[3] || cells[1] || cells[0] || {}).textContent || '').replace(/\\s+/g, ' ').trim();
      if (!courseName || courseName === '' || courseName === '课程名称' || courseName === 'Course Name') { continue; }

      var cellCount = cells.length;
      var academicYear = cellCount > 0 ? ((cells[0] || {}).textContent || '').replace(/\\s+/g, '').trim() : '';
      var courseCode = cellCount > 1 ? ((cells[1] || {}).textContent || '').replace(/\\s+/g, '').trim() : '';
      var courseSeq = cellCount > 2 ? ((cells[2] || {}).textContent || '').replace(/\\s+/g, '').trim() : '';
      var courseCategory = cellCount > 4 ? ((cells[4] || {}).textContent || '').trim() : '';
      var credit = cellCount > 5 ? ((cells[5] || {}).textContent || '').trim() : '';
      var finalExamScore = cellCount > 6 ? ((cells[6] || {}).textContent || '').trim() : '';
      var totalScore = cellCount > 7 ? ((cells[7] || {}).textContent || '').trim() : '';
      var makeupScore = cellCount > 8 ? ((cells[8] || {}).textContent || '').trim() : '';
      var finalScore = cellCount > 9 ? ((cells[9] || {}).textContent || '').trim() : '';
      var gradePoint = cellCount > 10 ? ((cells[10] || {}).textContent || '').trim() : '';

      grades.push({
        academicYear: academicYear,
        courseCode: courseCode,
        courseSeq: courseSeq,
        courseName: courseName,
        courseCategory: courseCategory,
        credit: credit,
        finalExamScore: finalExamScore,
        totalScore: totalScore,
        makeupScore: makeupScore,
        finalScore: finalScore,
        gradePoint: gradePoint
      });
    }

    var diagnostics = {
      currentUrl: window.location.href,
      pageTitle: document.title || '',
      tableSelector: resultName,
      rowCount: rows.length,
      parsedCount: grades.length,
      sampleRow: grades.length > 0 ? JSON.stringify(grades[0]) : 'none',
      allTablesOnPage: document.querySelectorAll('table').length,
      bodyLength: (document.body && document.body.innerHTML) ? document.body.innerHTML.length : 0,
      bodySnippet: (document.body ? (document.body.innerText || '') : '').substring(0, 300)
    };
    return JSON.stringify({ grades: grades, diagnostics: diagnostics, error: null });
  } catch(e) {
    return JSON.stringify({
      grades: [],
      diagnostics: {
        currentUrl: window.location.href,
        pageTitle: document.title || '',
        rowCount: 0,
        parsedCount: 0,
        sampleRow: 'exception: ' + (e && e.message),
        allTablesOnPage: 0,
        bodyLength: 0,
        bodySnippet: (document.body ? (document.body.innerText || '') : '').substring(0, 300)
      },
      error: 'parse error: ' + (e && e.message)
    });
  }
})();
`;
  }

  static buildUsualGradeScrapeScript(): string {
    return `
(function() {
  try {
    var tbody = document.querySelector('.gridtable tbody');
    if (!tbody) { tbody = document.querySelector('#grid18466436161 tbody'); }
    if (!tbody) { return JSON.stringify({ grades: [], diagnostics: { currentUrl: window.location.href, rowCount: 0, parsedCount: 0, sampleRow: 'tbody not found' }, error: '未找到平时成绩表格' }); }
    var rows = tbody.querySelectorAll('tr');
    var grades = [];
    for (var i = 0; i < rows.length; i++) {
      var cells = rows[i].querySelectorAll('td');
      if (cells.length < 7) {
        var ths = rows[i].querySelectorAll('th');
        if (ths.length > 0) { continue; }
      }
      var academicYear = (cells[0] || {}).textContent || '';
      academicYear = academicYear.replace(/\\s+/g, '').trim();
      var courseCode = (cells[1] || {}).textContent || '';
      courseCode = courseCode.replace(/\\s+/g, '').trim();
      var courseSeq = (cells[2] || {}).textContent || '';
      courseSeq = courseSeq.replace(/\\s+/g, '').trim();
      var courseName = (cells[3] || {}).textContent || '';
      courseName = courseName.replace(/\\s+/g, ' ').trim();
      var courseCategory = '';
      if (cells.length >= 5) { courseCategory = (cells[4] || {}).textContent || ''; courseCategory = courseCategory.trim(); }
      var credit = '';
      if (cells.length >= 6) { credit = (cells[5] || {}).textContent || ''; credit = credit.trim(); }
      var usualScore = '';
      if (cells.length >= 7) { usualScore = (cells[6] || {}).textContent || ''; usualScore = usualScore.trim(); }
      if (!courseName || courseName === '' || courseName === '课程名称') { continue; }
      var row = {
        academicYear: academicYear,
        courseCode: courseCode,
        courseSeq: courseSeq,
        courseName: courseName,
        courseCategory: courseCategory,
        credit: credit,
        finalExamScore: '',
        totalScore: usualScore,
        makeupScore: '',
        finalScore: '',
        gradePoint: ''
      };
      grades.push(row);
    }
    var diagnostics = {
      currentUrl: window.location.href,
      rowCount: rows.length,
      parsedCount: grades.length,
      sampleRow: grades.length > 0 ? JSON.stringify(grades[0]) : 'none'
    };
    return JSON.stringify({ grades: grades, diagnostics: diagnostics, error: null });
  } catch(e) {
    return JSON.stringify({ grades: [], error: 'parse error: ' + e.message });
  }
})();
`;
  }

  static buildSemesterSwitchScript(semesterId: number): string {
    return `
(function() {
  try {
    document.cookie = 'semester.id=${semesterId}; path=/eams; domain=eams.uestc.edu.cn';

    var idsInput = document.querySelector('input[name="ids"]');
    var idsValue = idsInput ? idsInput.value : '';
    if (!idsValue) {
      var semInput = document.querySelector('input[name="semester.id"]');
      if (semInput && semInput.value) {
        var formEl = semInput.closest('form');
        if (formEl) {
          var hiddenIds = formEl.querySelector('input[name="ids"]');
          if (hiddenIds) {
            idsValue = hiddenIds.value;
          }
        }
      }
    }

    var formData = 'ignoreHead=1&setting.kind=std&startWeek=1&project.id=1&isEng=0&semester.id=${semesterId}&ids=' + encodeURIComponent(idsValue);

    var xhr = new XMLHttpRequest();
    xhr.open('POST', 'courseTableForStd!courseTable.action', false);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.withCredentials = true;
    xhr.send(formData);

    if (xhr.status === 200) {
      var contentDiv = document.querySelector('.grid-container') || document.querySelector('#content') || document.querySelector('.content-container');
      if (contentDiv) {
        contentDiv.innerHTML = xhr.responseText;
      }
      var semInput2 = document.querySelector('input[name="semester.id"]');
      if (semInput2) {
        semInput2.value = '${semesterId}';
      }
      return JSON.stringify({ success: true, semesterId: ${semesterId} });
    } else {
      return JSON.stringify({ success: false, error: 'HTTP ' + xhr.status });
    }
  } catch(e) {
    return JSON.stringify({ success: false, error: e.message });
  }
})()
`;
  }

  static buildGetFormParamsScript(): string {
    return `
(function() {
  try {
    var semInput = document.querySelector('input[name="semester.id"]');
    var idsInput = document.querySelector('input[name="ids"]');
    return JSON.stringify({
      semesterId: semInput ? parseInt(semInput.value, 10) : 0,
      ids: idsInput ? idsInput.value : ''
    });
  } catch(e) {
    return JSON.stringify({ semesterId: 0, ids: '', error: e.message });
  }
})()
`;
  }

  static buildVpnSemesterSwitchScript(semesterId: number, vpnActionUrl: string): string {
    return `
(function() {
  try {
    var idsInput = document.querySelector('input[name="ids"]');
    var idsValue = idsInput ? idsInput.value : '';
    if (!idsValue) {
      var semInput = document.querySelector('input[name="semester.id"]');
      if (semInput && semInput.value) {
        var formEl = semInput.closest('form');
        if (formEl) {
          var hiddenIds = formEl.querySelector('input[name="ids"]');
          if (hiddenIds) {
            idsValue = hiddenIds.value;
          }
        }
      }
    }

    var formData = 'ignoreHead=1&setting.kind=std&startWeek=1&project.id=1&isEng=0&semester.id=${semesterId}&ids=' + encodeURIComponent(idsValue);

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '${vpnActionUrl}', false);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.withCredentials = true;
    xhr.send(formData);

    if (xhr.status === 200) {
      var contentDiv = document.querySelector('.grid-container') || document.querySelector('#content') || document.querySelector('.content-container');
      if (contentDiv) {
        contentDiv.innerHTML = xhr.responseText;
      }
      var semInput2 = document.querySelector('input[name="semester.id"]');
      if (semInput2) {
        semInput2.value = '${semesterId}';
      }
      return JSON.stringify({ success: true, semesterId: ${semesterId} });
    } else {
      return JSON.stringify({ success: false, error: 'HTTP ' + xhr.status });
    }
  } catch(e) {
    return JSON.stringify({ success: false, error: e.message });
  }
})()
`;
  }
}
