# Retrieving Prior HTML Reports Without Misidentifying the Deliverable

Use this when a user says an HTML report, plan, or strategy page is missing, incomplete, overwritten, or "not the one".

## Core distinction

A matching filename or title is not sufficient evidence that you found the intended deliverable. Report corpora often contain several related artifacts:

- strategy / content-core report
- engineering implementation plan
- code-gap audit
- operational playbook
- final consolidated report
- supporting research report

A later engineering report may reuse the same project name and even call itself a "marketing plan" while omitting the original content strategy.

## Retrieval workflow

1. Search the static report root by likely project and topic terms.
2. Search past sessions for the same concepts, not only the guessed filename.
3. Inspect headings and representative body sections of every plausible artifact.
4. Classify each candidate by purpose:
   - strategic narrative
   - content system
   - distribution / backlinks
   - technical implementation
   - audit / gap analysis
   - execution checklist
5. Verify each candidate URL returns HTTP 200.
6. Respond with an artifact map and state which page is the best match.
7. If the intended material is fragmented, say so explicitly and recommend a consolidated report rather than claiming a single page is the original.

## Useful search concepts

For marketing strategy retrieval, search for terms such as:

- 内容核心 / 内容策略 / 内容矩阵
- 飞轮 / SEO / 外链 / 分发
- Reply Guy / Twitter / Skill
- 关键词体系 / 选题系统
- 30 / 60 / 90 天
- code gaps / roadmap / audit

## Pitfall

Do not conclude "the report still exists" merely because one similarly named HTML file is accessible. First confirm that its body contains the user's expected strategic substance. Filename-level recovery is not content-level recovery.
