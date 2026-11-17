"""What a build did, for Dev Lab ▸ Builds (docs/roadmap.md 21.7).

A build's row keeps the model conversation, the draft and the counters
(src/build_store.py). The athlete's screens read none of that
(`build_store.public`); this reads it for whoever started the build — each
turn's tool calls and what they answered, each check's problems and the
program the model was shown, the tokens and what they cost — the only way to
judge what the builder is good at and what it costs. Pure over a row.
"""
from __future__ import annotations

import json

_SAID = 1200            # characters of a turn's own words kept
_RESULT = 400           # characters of a tool's answer kept
_NOT_FINISHED = 'not finished: the draft does not pass — '


def _prices() -> tuple[dict, str]:
    from src import package_builder
    return package_builder.PRICE, package_builder.MODEL


def cost_usd(usage: dict) -> float:
    """What the tokens cost at the builder model's list price (web searches
    are billed apart and are not in it)."""
    price, _ = _prices()
    return round(sum((usage.get(k) or 0) * p for k, p in price.items()) / 1e6, 4)


def usage_of(row: dict) -> dict:
    used = row.get('usage') or {}
    return {'turns': used.get('turns') or 0, 'checks': used.get('checks') or 0,
            'inputTokens': used.get('input_tokens') or 0, 'outputTokens': used.get('output_tokens') or 0,
            'cacheReadTokens': used.get('cache_read_input_tokens') or 0,
            'cacheWriteTokens': used.get('cache_creation_input_tokens') or 0,
            'webSearches': used.get('web_searches') or 0, 'webFetches': used.get('web_fetches') or 0,
            'seconds': used.get('seconds') or 0, 'model': used.get('model')}


def summary(row: dict) -> dict:
    """One build as the list shows it: how it ended and what it spent."""
    from src import build_store
    request = row.get('request') or {}
    return {**build_store.public(row), 'attempts': row.get('attempts') or 0, 'usage': usage_of(row),
            'costUsd': cost_usd(row.get('usage') or {}), 'webSearch': bool(request.get('webSearch')),
            'pastedChars': len(request.get('pastedText') or '')}


def totals(summaries: list[dict]) -> dict:
    """The listed builds together."""
    by_status: dict = {}
    for s in summaries:
        by_status[s['status']] = by_status.get(s['status'], 0) + 1
    ended = [s for s in summaries if s['status'] in ('done', 'failed')]
    add = lambda key: sum(s['usage'][key] for s in summaries)    # noqa: E731
    return {'builds': len(summaries), 'byStatus': by_status,
            'doneShare': round(by_status.get('done', 0) / len(ended), 2) if ended else None,
            'inputTokens': add('inputTokens'), 'outputTokens': add('outputTokens'),
            'cacheReadTokens': add('cacheReadTokens'), 'cacheWriteTokens': add('cacheWriteTokens'),
            'seconds': round(add('seconds'), 1), 'costUsd': round(sum(s['costUsd'] for s in summaries), 2)}


def _blocks(message: dict) -> list[dict]:
    content = message.get('content')
    if isinstance(content, str):
        return [{'type': 'text', 'text': content}]
    return [b for b in content or [] if isinstance(b, dict)]


def _text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return ' '.join(b.get('text') or '' for b in content if isinstance(b, dict))
    return '' if content is None else json.dumps(content)


def _short(text: str, limit: int) -> str | None:
    text = (text or '').strip()
    if not text:
        return None
    return text if len(text) <= limit else text[:limit].rstrip() + '…'


def _check_of(tool: str, answer: str) -> dict | None:
    """The gate's answer inside a tool result: `check_package`'s, or the one a
    refused `finish` carries. None for anything else (a `finish` that passed
    says only that it finished)."""
    if tool == 'finish' and answer.startswith(_NOT_FINISHED):
        answer = answer[len(_NOT_FINISHED):]
    elif tool != 'check_package':
        return None
    try:
        result = json.loads(answer)
    except ValueError:
        return None
    if not isinstance(result, dict) or 'ok' not in result:
        return None
    out = {'ok': bool(result['ok']),
           'problems': [{k: p.get(k) for k in ('stage', 'code', 'file', 'message')}
                        for p in result.get('problems') or [] if isinstance(p, dict)],
           'moreProblems': result.get('more_problems') or 0,
           'warnings': [w if isinstance(w, str) else str(w.get('message') or w.get('code') or w)
                        for w in result.get('warnings') or []],
           'skipped': result.get('skipped') or [], 'checksLeft': result.get('checks_left'), 'athlete': None}
    probe = result.get('for_this_athlete')
    if isinstance(probe, dict):
        out['athlete'] = {'as': probe.get('as'), 'feasible': probe.get('feasible'), 'error': probe.get('error'),
                          'errors': probe.get('errors') or [], 'weeks': probe.get('weeks'),
                          'checkThese': probe.get('check_these') or [], 'program': probe.get('program'),
                          'moreTracks': len(probe.get('more_tracks') or [])}
    return out


def _call(block: dict, results: dict, checks: list, turn: int) -> dict:
    name, args = block.get('name'), block.get('input') if isinstance(block.get('input'), dict) else {}
    result = results.get(block.get('id')) or {}
    answer = _text(result.get('content'))
    call = {'tool': name, 'path': args.get('path'), 'kind': args.get('kind'),
            'bytes': len(args['content'].encode('utf-8')) if isinstance(args.get('content'), str) else None,
            'query': None, 'error': bool(result.get('is_error')), 'result': _short(answer, _RESULT), 'check': None}
    check = _check_of(name, answer)
    if check is not None:
        call['check'] = len(checks)
        call['result'] = 'passes' if check['ok'] else f"{len(check['problems']) + check['moreProblems']} to fix"
        checks.append({'turn': turn, 'tool': name, **check})
    elif name in ('finish', 'decline'):
        call['result'] = _short(args.get('summary') or args.get('reason') or answer, _RESULT)
    return call


def _tokens(entry: dict | None) -> dict | None:
    if not entry:
        return None
    return {'input': entry.get('in') or 0, 'output': entry.get('out') or 0, 'cacheRead': entry.get('cached') or 0,
            'cacheWrite': entry.get('written') or 0}


def conversation(transcript: list, per_turn: list | None = None) -> tuple[list[dict], list[dict], list[dict]]:
    """The model's turns as kept in the transcript, the checks among them and
    the turns that were thrown away (cut off at the output limit: counted and
    paid for, nothing of them kept). → (turns, checks, dropped)."""
    per_turn = [t for t in per_turn or [] if isinstance(t, dict)]
    kept = [t for t in per_turn if t.get('kept')]
    dropped = [{'stop': t.get('stop'), 'tokens': _tokens(t)} for t in per_turn if not t.get('kept')]
    results = {b.get('tool_use_id'): b for m in transcript if m.get('role') == 'user'
               for b in _blocks(m) if b.get('type') == 'tool_result'}
    turns: list[dict] = []
    checks: list[dict] = []
    for index, message in enumerate(transcript):
        blocks = _blocks(message)
        if message.get('role') != 'assistant':
            # The first message is the request; any later text is the loop's own nudge.
            note = _short(' '.join(b.get('text') or '' for b in blocks if b.get('type') == 'text'), _RESULT)
            if index and note and turns:
                turns[-1]['note'] = note
            continue
        number = len(turns) + 1
        calls = []
        for block in blocks:
            if block.get('type') == 'tool_use':
                calls.append(_call(block, results, checks, number))
            elif block.get('type') == 'server_tool_use':
                asked = block.get('input') if isinstance(block.get('input'), dict) else {}
                calls.append({'tool': block.get('name'), 'path': None, 'kind': None, 'bytes': None,
                              'query': asked.get('query') or asked.get('url'), 'error': False, 'result': None,
                              'check': None})
        said = ' '.join((b.get('text') or '').strip() for b in blocks if b.get('type') == 'text')
        turns.append({'n': number, 'said': _short(said, _SAID),
                      'thought': any(b.get('type') in ('thinking', 'redacted_thinking') for b in blocks),
                      'calls': calls, 'note': None,
                      'tokens': _tokens(kept[number - 1]) if number <= len(kept) else None})
    return turns, checks, dropped


def problem_counts(checks: list[dict]) -> list[dict]:
    """How often each kind of problem came up over the build's checks, most
    frequent first: what the model keeps getting wrong."""
    counts: dict = {}
    for check in checks:
        for p in check['problems']:
            key = (p.get('stage') or '', p.get('code') or '')
            counts[key] = counts.get(key, 0) + 1
    return [{'stage': stage or None, 'code': code or None, 'count': n}
            for (stage, code), n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))]


def detail(row: dict) -> dict:
    """One build in full: the request, the turns, the checks and the draft as
    it stands (the installed files when it finished)."""
    from src import package_builder
    request = row.get('request') or {}
    turns, checks, dropped = conversation(row.get('transcript') or [], (row.get('usage') or {}).get('per_turn'))
    files = row.get('draft_files') or {}
    return {**summary(row),
            'request': {'description': request.get('description') or '', 'answers': request.get('answers') or {},
                        'pastedText': request.get('pastedText') or '', 'webSearch': bool(request.get('webSearch')),
                        'revise': request.get('revise')},
            'turns': turns, 'droppedTurns': dropped, 'checks': checks, 'problemCounts': problem_counts(checks),
            'files': [{'path': p, 'bytes': len(files[p].encode('utf-8')), 'content': files[p]} for p in sorted(files)],
            'limits': {'turns': package_builder.LIMITS['turns'], 'checks': package_builder.LIMITS['checks'],
                       'outputTokens': package_builder.LIMITS['output_tokens'],
                       'seconds': package_builder.LIMITS['seconds']},
            'effort': package_builder.effort(), 'priceModel': package_builder.MODEL}
