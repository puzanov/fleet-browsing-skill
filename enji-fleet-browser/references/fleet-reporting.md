# Fleet Reporting

Use this reference when the task asks to monitor, compare, evaluate, or user-test one or more websites.

## Evidence Layout

Create one directory per run and one subdirectory per site/page:

```text
/tmp/enji-fleet-browser/<run-id>/
  index.md
  site-a/
    requested-url.txt
    final-url.txt
    title.txt
    snapshot.txt
    body.txt
    body.html
    page.png
    extracted.json
  site-b/
    ...
```

Always capture the final URL and current date/time in the run summary. For claims about design, pricing, copy, inventory, funnels, or broken UX, keep a screenshot or extracted source file.

## Competitor Monitoring Checklist

For each competitor page, collect only fields relevant to the user's question:

- URL requested and final URL after redirects.
- Page title, primary headline, CTA text, navigation labels.
- Pricing, plan names, discounts, availability, shipping, legal footnotes.
- Product/service claims, integrations, supported regions, guarantees.
- Signup/demo/purchase funnel steps and any friction.
- Visual evidence: full-page screenshot and annotated screenshot when refs matter.
- Structured JSON for repeated cards, tables, plans, search results, or catalog items.
- Notable changes from prior evidence if the user provides a baseline.

Prefer structured extraction for tables/cards. Markdown/text dumps are acceptable for prose pages.

## User-Testing Notes

Act like a realistic user with a goal:

1. State the user goal in the run summary.
2. Follow the visible navigation instead of jumping directly to hidden endpoints unless the user asks for endpoint inspection.
3. After every action, record what changed: URL, visible state, errors, blockers, load delays, confusing labels.
4. Capture screenshots at decision points, not every tiny step.
5. Separate facts from interpretation. A missing button, disabled form, or visible error is a fact; "confusing" or "high friction" is an assessment supported by facts.

For image and media findings, test the state a user can actually see:

- Scroll through the page before taking a full-page screenshot because browser full-page screenshots do not necessarily trigger lazy-load observers.
- Open each relevant tab, carousel slide, accordion, or modal before judging media inside it.
- Treat hidden/offscreen lazy placeholders (`/nuxt-lazy-load-fallback.svg`, `data-src`, `complete=false`, or `naturalWidth=0`) as inconclusive unless the element is visible after user-like scrolling/interaction and a short wait.
- Report a broken image only when the visible state still shows a placeholder/blank image or the actual media URL fails, and cite the screenshot plus the image audit/DOM evidence.

## Block Classification

Mark a page as `blocked` only when evidence shows a challenge or automation block:

- Challenge/security copy such as Cloudflare, Turnstile, captcha, access denied, unusual traffic, checking browser, or verify human.
- HTTP-like block text such as 403/429/Forbidden inside the rendered page or command output.
- Expected public content is replaced by a generic interstitial or empty shell.

When blocked, save the normal `agent-browser` evidence first, then switch to
`references/obscura-stealth-fallback.md`. Do not keep probing the blocked page
with the normal browser path after a block signal is visible.

If the stealth fallback also shows a challenge, report the page as blocked and
include both evidence paths. Treat that as a collection limitation. For
third-party destinations, do not turn the automation block into a target-site UX
finding unless the target site's own rendered evidence proves the issue.

## Report Shape

Keep the final report concise:

```text
Scope:
Sites/pages checked, timestamp, environment assumptions.

Findings:
1. Finding with evidence file path.
2. Finding with evidence file path.

Extracted Data:
Small table or JSON summary, with source artifact paths.

Limitations:
Blocked pages, auth requirements, dynamic content that could not be verified.
```

Do not paste huge HTML, HAR, cookies, or secrets into the final response.
