# LWC AgentGPT – Deploy from this folder

This folder contains everything needed to deploy the AgentGPT conversation viewer to a Salesforce org. Use it after cloning or downloading the repo.

## Prerequisites

- **Salesforce CLI** (2.0+): `sf version`
- **Org with**: Data Cloud enabled, Agentforce / Session Tracing data model, and (for AI titles) an Einstein Prompt Template

## 1. Authenticate

```bash
sf org login web -a myOrg
```

Replace `myOrg` with your org alias.

## 2. Prompt template (for AI-generated session titles)

The app uses the prompt template **agent_session_summarizer** to generate conversation titles.

- **If this folder includes `force-app/main/default/genAiPromptTemplates/`**  
  It will be deployed with the rest of the source. Ensure the template’s API name matches what the Apex expects (see `AgentGPTController.cls`: `PROMPT_TEMPLATE_NAME`).

- **If `genAiPromptTemplates/` is not present**  
  Either create the template in Setup (Prompt Builder) with API name `Agent_Session_Summarizer` (or update the constant in `AgentGPTController.cls`), or retrieve it from an org that has it:

  ```bash
  sf project retrieve start -m GenAiPromptTemplate:agent_session_summarizer -o myOrg
  ```

  Then copy the retrieved `force-app/main/default/genAiPromptTemplates/` into this folder’s `force-app/main/default/` and deploy again.

## 3. Deploy

From this folder (`deploy/`):

```bash
cd deploy
sf project deploy start -o myOrg
```

Wait for **Status: Succeeded**.

## 4. Add components to a page

- **Full conversation viewer**  
  Setup → Lightning App Builder → New → App Page → name (e.g. "Agent Conversations") → add **Agent GPT - Conversation Viewer** → Save → Activate → assign to app.

- **Home tab widget (optional)**  
  Edit the app Home page in Lightning App Builder → add **Agent Sessions (Home)** → Save → Activate.

## 5. Verify

- Open the app page; you should see the sidebar and session list (or “No conversations found” if there’s no data).
- Run Apex tests: `sf apex run test -o myOrg -n AgentGPTControllerTest -r human`

## Data Cloud

The component reads from Data Cloud’s Session Tracing data model (e.g. `ConversationSession__dlm`, `ConversationMessage__dlm`). If your org uses different object or field names, update the SQL and mapping in `AgentGPTController.cls`.

## Static resources

Images (AgentAstro, LWCLoadingIcon) are included in `force-app/main/default/staticresources/` and are deployed with the project. The LWC references them via `@salesforce/resourceUrl`.
