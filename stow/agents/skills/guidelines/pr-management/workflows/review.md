# Review a PR

Assess the actual change against its purpose and repository contracts.

1. [Inspect](../capabilities/inspect.md) the PR and relevant design input.
2. Create an independent [review checkout](../capabilities/review-checkout.md). Review the recorded head against the appropriate merge base, inspecting surrounding code as needed.
3. [Assess](../capabilities/assess.md) correctness, design, compatibility and failure handling. [Verify](../capabilities/verify.md) consequential claims with proportional checks.
4. Report actionable findings with code locations, evidence, impact and expected behavior. Separate defects from optional improvements and unanswered questions.
5. Preserve the report outside the temporary clone and clean up through the checkout capability, including on early exit where possible.

A review request produces an assessment; publish a GitHub review only when requested. State the reviewed revisions and limits. No findings means none were identified within that scope, not proof of correctness. If asked about readiness, include required checks, approval state and mergeability; distinguish unknown state from readiness.
