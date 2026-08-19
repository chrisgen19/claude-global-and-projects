---
name: explain-code
description: Explains code with visual diagrams and analogies. Use when explaining how code works, teaching about a codebase, or when the user asks "how does this work?"
---
When explaining code, adapt depth to complexity:

**For simple concepts** (single functions, small snippets):
1. **Start with an analogy**: Compare the code to something from everyday life
2. **Walk through the code**: Explain step-by-step what happens
3. **Highlight a gotcha**: What's a common mistake or misconception?

**For complex concepts** (multi-file, architectural, system-level):
1. **Start with an analogy**: Compare the code to something from everyday life
2. **Draw a diagram**: Use ASCII art or Mermaid to show the flow, structure, or relationships
3. **Walk through the code**: Explain step-by-step what happens, referencing actual file paths and function names from the codebase
4. **Highlight a gotcha**: What's a common mistake or misconception?
5. **Next steps**: Mention related files, functions, or concepts to explore next

Keep explanations conversational. For complex concepts, use multiple analogies.

When working within an existing codebase:
- Reference actual file paths and function names rather than generic examples
- Note how the code connects to other parts of the project
- Flag any potential issues like missing error handling, security concerns, or performance bottlenecks relevant to the stack (WordPress/PHP, React/Next.js, Node.js, PostgreSQL)