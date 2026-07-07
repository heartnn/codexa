// Auto-marks a book "read" once its saved progress crosses a completion threshold.
//
// Why this exists: CXReader's percentage (public/js/cxreader/index.js makePct()) is a fraction
// of pages read within the spine and never actually reaches 1.0 for paginated content — the last
// page of the last chapter yields (pageCount-1)/pageCount, not 1. So a book a user has genuinely
// finished never satisfies a raw `percentage >= 1` check, and its read_status never advances past
// 'reading' on its own — it lingers in the "Currently reading" shelf forever. 0.95 mirrors the
// threshold already used for "books completed" in server/routes/stats.js.
//
// Called from every route that writes reading_progress.percentage (server/routes/progress.js,
// server/routes/kosync.js — both the internal PUT and the external-facing /syncs/progress PUT).
// Those routes use different hash flavors for the same book (Codexa's own file_hash for the web
// reader, KOReader's partial-MD5 file_hash_md5/kosync_hash override for KOSync clients), so this
// matches against all three rather than assuming one.
const { getDb } = require('../db');
const bookorbit = require('../services/bookorbitSync');

const FINISHED_THRESHOLD = 0.95;

function maybeMarkBookFinished(userId, documentHash) {
  if (!documentHash) return;
  const db = getDb();
  const progress = db.prepare(
    'SELECT percentage FROM reading_progress WHERE user_id = ? AND document_hash = ?'
  ).get(userId, documentHash);
  if (!progress || progress.percentage < FINISHED_THRESHOLD) return;

  const book = db.prepare(
    'SELECT id, read_status FROM books WHERE user_id = ? AND (file_hash = ? OR file_hash_md5 = ? OR kosync_hash = ?) LIMIT 1'
  ).get(userId, documentHash, documentHash, documentHash);
  // Never override a status the user already set deliberately.
  if (!book || book.read_status === 'read' || book.read_status === 'abandoned') return;

  db.prepare(`UPDATE books SET read_status = 'read', status_modified = strftime('%s','now') WHERE id = ?`).run(book.id);
  bookorbit.triggerSync(userId, book.id);
}

module.exports = { maybeMarkBookFinished, FINISHED_THRESHOLD };
