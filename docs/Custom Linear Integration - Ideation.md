# Custom Linear Integration - Ideation

## Overview

Linear Notes could connect to the official Linear app through a custom integration. The integration would use Linear's GraphQL API for reading and writing data, OAuth for workspace authorization, and webhooks for near-real-time updates.

The strongest product direction is to keep Linear as the operational source of truth while making Linear Notes the calmer local workspace for drafting, reading, planning, and long-form thinking.

## Ideas

### 1. Linear Docs Sync

Documents created inside Linear projects would be linked to Markdown notes in Linear Notes. Changes made in either place would update the other.

Conceptually:

```text
Linear Project
  -> Linear Document
       <-> Linear Notes Markdown file
```

This is possible. Linear exposes Documents through its API and supports document webhook events, including create, update, and remove actions. Documents use Markdown-like content, which gives us a practical format for local notes.

The difficult part is reliable two-way synchronization:

- Detecting and preventing update loops
- Handling edits made offline
- Detecting simultaneous changes
- Preserving mentions, links, images, and formatting
- Deciding what happens when a document is deleted
- Keeping local files safe from silent overwrites

Each linked note could store integration metadata in YAML frontmatter:

```yaml
---
linearDocumentId: document-id
linearProjectId: project-id
linearDocumentUrl: https://linear.app/example/document/...
lastSyncedAt: 2026-09-07T10:30:00Z
---
```

When both versions change, Linear Notes should show a conflict state and let the user keep the local version, use the Linear version, or keep both. It should not silently choose a winner.

#### Infrastructure consideration

Linear webhooks require a publicly reachable HTTPS endpoint. A local-only macOS app cannot reliably receive webhook events while it is closed. Reliable two-way sync would therefore need a small hosted sync relay, or a less reliable polling approach that runs while Linear Notes is open.

### 2. Linear Docs Port

Linear Notes would import existing Linear documents as local Markdown files.

This is the simplest and lowest-risk feature. A possible flow:

```text
Import from Linear
  -> Choose workspace
  -> Choose project
  -> Choose documents
  -> Import as Markdown notes
```

The imported note could retain:

- Document title
- Markdown content
- Linear document ID
- Linear project ID
- Linear document URL
- Creation and update dates
- Links and supported mentions

The user could choose between three modes:

1. Import once
2. Import and keep linked
3. Import all documents from a project

This feature would provide immediate value while also creating the foundation for future two-way sync.

### 3. Linear Projects Sync

Linear Notes could display a local browser or index of the user's Linear projects.

```text
Projects
  Active
    Project Alpha
    Project Beta
  Planned
  Completed
```

Project entries could show:

- Project name
- Status
- Lead
- Team
- Start and target dates
- Progress
- Project URL
- Associated Linear documents
- Linked local notes

This is very feasible. The first version should be read-only, with Linear remaining the source of truth for project metadata. Project editing could be considered later if there is a clear workflow that benefits from it.

## Feasibility Summary

| Feature | Feasible? | Complexity | Recommended approach |
| --- | --- | --- | --- |
| Linear Docs Sync | Yes | High | Linked notes, webhooks, conflict detection |
| Linear Docs Port | Yes | Low to medium | One-click import with optional linking |
| Linear Projects Sync | Yes | Low | Read-only project browser and index |

## Proposed Architecture

### Local macOS application

The app would handle:

- Connecting the user's Linear workspace
- Browsing projects and documents
- Importing documents into the selected notes folder
- Editing local Markdown files
- Showing sync state and conflicts
- Opening the corresponding item in Linear

### Linear API connection

The integration would use OAuth rather than requiring the user to paste a personal API key. Linear recommends OAuth for applications that integrate with other users' workspaces.

The connection would need permission to read and, for two-way sync, write projects and documents.

### Optional sync relay

A small hosted service would handle:

- OAuth callback processing
- Secure token storage
- Linear webhook reception
- Webhook signature verification
- Queuing and retrying changes
- Mapping Linear document IDs to local note IDs

The relay would not need to store full note content if the product is designed carefully. It could primarily coordinate events and leave the Markdown files on the user's Mac. However, fully reliable delivery to an offline Mac would require some durable event or change storage.

## Synchronization Rules

The integration should define these rules before implementation:

- Every linked note has a stable Linear document ID.
- Every imported document keeps a link back to Linear.
- Changes created by the integration include a source marker so they do not trigger an endless loop.
- The latest known version or revision is stored locally.
- Conflicts are surfaced rather than silently overwritten.
- Deleting a Linear document does not immediately delete the local note; it moves the note to an unlinked state and asks the user what to do.
- Disconnecting Linear leaves local Markdown files untouched.
- A failed sync never blocks local editing.

## Recommended Rollout

### Phase 1: Project browser

- Connect Linear with OAuth
- List projects
- Show project metadata and links
- Show the project's documents
- Open projects and documents in Linear

### Phase 2: Document port

- Import one or more Linear documents
- Save them as Markdown notes
- Store document and project IDs in frontmatter
- Offer import-once and keep-linked choices

### Phase 3: Linked document refresh

- Refresh linked documents from Linear
- Detect whether the local file has changed
- Show a preview before overwriting local content
- Add manual push and pull actions

### Phase 4: Two-way sync

- Add the hosted webhook relay
- Push local edits to Linear
- Receive Linear edits through webhooks
- Add conflict handling and retry states
- Add connection and sync diagnostics

## Product Positioning

Linear Notes should not try to replace Linear. The two tools have different strengths:

| Linear | Linear Notes |
| --- | --- |
| Projects, issues, statuses, ownership | Drafting, thinking, reading, and local writing |
| Team coordination and operational history | Private local files and low-friction editing |
| Structured execution | Flexible long-form context |

The most coherent experience is a connected pair:

```text
Think and draft in Linear Notes
  -> Link or publish the useful outcome to Linear
  -> Track execution in Linear
  -> Read project context back in Linear Notes
```

## Initial Recommendation

Build the read-only project browser and Linear Docs port first. They are useful without requiring a server, establish the data model for linked notes, and let the workflow prove itself before introducing the complexity of continuous two-way synchronization.

The first milestone could be:

> Connect Linear, choose a project, import a document into the local notes folder, and open the original document in Linear at any time.

## References

- [Linear Documents](https://linear.app/docs/documents)
- [Linear Project Overview](https://linear.app/docs/project-overview)
- [Linear GraphQL API](https://linear.app/developers/graphql)
- [Linear Webhooks](https://linear.app/developers/webhooks)
- [Linear OAuth 2.0 Authentication](https://linear.app/developers/oauth-2-0-authentication)
- [Linear Integration Directory](https://linear.app/docs/integration-directory)
