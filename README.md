# LWC AgentGPT – Deploy from this folder

This folder contains everything needed to deploy the AgentGPT conversation viewer to a Salesforce org. Use it after cloning or downloading the repo.

**Included in this deploy:** The **Agent Conversations** custom tab and its Lightning App Page (with the Conversation Viewer component) are in source. After deploy, add the tab to your app and optionally add the Home widget (see step 4).

## Prerequisites

- **Salesforce CLI** (2.0+): `sf version`
- **Org with**: Data Cloud enabled, Agentforce / Session Tracing data model, and (for AI titles) an Einstein Prompt Template
- **Users of the components** must have the **Data Cloud User** permission set and either **Prompt Template User** or **Prompt Template Manager** applied (for viewing conversations and AI-generated titles).

## 1. Authenticate

```bash
sf org login web -a myOrg
```

Replace `myOrg` with your org alias.

## 2. Prompt template (for AI-generated session titles)

The app uses the prompt template **Agent_Session_Summarizer** to generate conversation titles.

- **If this folder includes `force-app/main/default/genAiPromptTemplates/`**  
  The template will be deployed with the rest of the source. Ensure the template’s API name matches what the Apex expects (see `AgentGPTController.cls`: `PROMPT_TEMPLATE_NAME`).

- **Activating the template after deploy**  
  The template metadata includes `<activeVersion>2</activeVersion>` so the template is intended to deploy as **Active** with **Version 2** (API 62.0–compatible; newer API versions may use `activeVersionIdentifier`). If the template is still **Inactive** after deploy, activate it once: Setup → Prompt Builder → **Agent_Session_Summarizer** → Activate.

- **If `genAiPromptTemplates/` is not present**  
  Either create the template in Setup (Prompt Builder) with API name `Agent_Session_Summarizer` (or update the constant in `AgentGPTController.cls`), or retrieve it from an org that has it:

  ```bash
  sf project retrieve start -m GenAiPromptTemplate:Agent_Session_Summarizer -o myOrg
  ```

  Then copy the retrieved `force-app/main/default/genAiPromptTemplates/` into this folder’s `force-app/main/default/` and deploy again.

## 3. Deploy

From this folder (`deploy/`):

```bash
cd deploy
sf project deploy start -o myOrg
```

Wait for **Status: Succeeded**.

## 4. Tab visibility and add the tab to your app

The **Agent Conversations** tab and its App Page (Conversation Viewer) are deployed with this project. The tab may be **hidden by default** for all users. This package includes the permission set **Agent Conversations LWC Visibility**, which grants visibility to the tab for any user (or profile) it is assigned to.

**Make the tab visible:**

- **For System Administrator (recommended after deploy):**  
  Setup → **Profiles** → **System Administrator** → **Permission Set Assignments** → **Manage Assignments** → assign **Agent Conversations LWC Visibility**. All users with the System Administrator profile will then see the tab (after adding it to the app; see below).

- **For other users or profiles:**  
  Setup → **Permission Sets** → **Agent Conversations LWC Visibility** → **Manage Assignments** → add the users or assign the permission set to the desired profile. Any user who has **Agent Conversations LWC Visibility** assigned will have visibility to the Agent Conversations tab.

**Add the tab to your Lightning app:**

- **Add the tab to your Lightning app**  
  Setup → App Manager → select your app → Edit → **Navigation Items** → add **Agent Conversations** → Save.

- **Home tab widget (optional)**  
  Edit the app Home page in Lightning App Builder → add **Agent Sessions (Home)** → Save → Activate.

**Post-deploy checklist:** (1) Assign **Agent Conversations LWC Visibility** to the System Administrator profile (and any other users/profiles as needed). (2) Add the **Agent Conversations** tab to your app's navigation items.

## 5. Verify

- Open the **Agent Conversations** tab in your app; you should see the sidebar and session list (or “No conversations found” if there’s no data).
- Run Apex tests: `sf apex run test -o myOrg -n AgentGPTControllerTest -r human`

## Data Cloud

The component reads from Data Cloud’s Session Tracing data model (e.g. `ConversationSession__dlm`, `ConversationMessage__dlm`). If your org uses different object or field names, update the SQL and mapping in `AgentGPTController.cls`.

## Static resources

Images (AgentAstro, LWCLoadingIcon) are included in `force-app/main/default/staticresources/` and are deployed with the project. The LWC references them via `@salesforce/resourceUrl`.
