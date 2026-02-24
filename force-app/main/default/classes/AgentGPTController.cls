/**
 * @description Controller for the AgentGPT Lightning Web Component
 * Retrieves Agentforce Employee Agent conversation history from Data Cloud
 * and generates AI-powered session titles using Einstein Prompt Templates
 */
public with sharing class AgentGPTController {
    
    // Prompt Template API Name - update this based on your org configuration
    private static final String PROMPT_TEMPLATE_NAME = 'Agent_Session_Summarizer';
    private static final Integer MAX_ROWS_LIMIT = 2000;
    
    /**
     * @description Retrieves user's agent sessions from Data Cloud within the specified timeframe
     * @param daysLookback Number of days to look back (7, 30, or 90)
     * @return List of SessionWrapper objects containing session and message data
     */
    @AuraEnabled(cacheable=true)
    public static List<SessionWrapper> getUserSessions(Integer daysLookback) {
        try {
            // Validate input
            if (daysLookback == null || daysLookback <= 0) {
                daysLookback = 7;
            }
            
            // Get current user ID for security filtering
            String currentUserId = UserInfo.getUserId();
            
            // Construct the Data Cloud SQL query
            String sqlQuery = buildSessionQuery(daysLookback, currentUserId);
            
            // Execute the query via Data Cloud Connect API
            ConnectApi.QuerySqlInput queryInput = new ConnectApi.QuerySqlInput();
            queryInput.sql = sqlQuery;
            
            ConnectApi.QuerySqlOutput queryOutput = ConnectApi.CdpQuery.querySql(queryInput);
            
            // Transform flat SQL results into hierarchical structure
            return transformQueryResults(queryOutput);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching sessions: ' + e.getMessage());
        }
    }
    
    /**
     * @description Returns the current user's timezone ID (e.g. America/Los_Angeles) for consistent date/time display in LWC.
     * @return IANA timezone string from the user's Salesforce locale
     */
    @AuraEnabled(cacheable=true)
    public static String getCurrentUserTimeZone() {
        return UserInfo.getTimeZone().getID();
    }
    
    /**
     * @description Retrieves paginated recent sessions for the home tab component (5 per page)
     * @param pageSize Number of sessions per page (default 5)
     * @param pageNumber 1-based page number
     * @return PaginatedSessionsWrapper with sessions for the page and total count
     */
    @AuraEnabled(cacheable=false)
    public static PaginatedSessionsWrapper getRecentSessionsForHome(Integer pageSize, Integer pageNumber) {
        try {
            if (pageSize == null || pageSize <= 0) {
                pageSize = 5;
            }
            if (pageNumber == null || pageNumber <= 0) {
                pageNumber = 1;
            }
            Integer daysLookback = 90;
            String currentUserId = UserInfo.getUserId();
            String sqlQuery = buildSessionQuery(daysLookback, currentUserId);
            ConnectApi.QuerySqlInput queryInput = new ConnectApi.QuerySqlInput();
            queryInput.sql = sqlQuery;
            ConnectApi.QuerySqlOutput queryOutput = ConnectApi.CdpQuery.querySql(queryInput);
            List<SessionWrapper> allSessions = transformQueryResults(queryOutput);
            if (allSessions != null && !allSessions.isEmpty()) {
                logSessionSortDiagnostics('Before sort', allSessions);
                allSessions = sortSessionsNewestFirst(allSessions);
                logSessionSortDiagnostics('After sort', allSessions);
            }
            Integer totalCount = allSessions.size();
            Integer startIndex = (pageNumber - 1) * pageSize;
            String userTimeZone = UserInfo.getTimeZone().getID();
            if (startIndex >= totalCount) {
                return new PaginatedSessionsWrapper(new List<SessionWrapper>(), totalCount, userTimeZone);
            }
            Integer endIndex = Math.min(startIndex + pageSize, totalCount);
            List<SessionWrapper> pageSessions = new List<SessionWrapper>();
            for (Integer i = startIndex; i < endIndex; i++) {
                pageSessions.add(allSessions[i]);
            }
            return new PaginatedSessionsWrapper(pageSessions, totalCount, userTimeZone);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching recent sessions: ' + e.getMessage());
        }
    }

    /**
     * @description Generates a session title using Einstein Prompt Template
     * @param conversationContext String containing the first few messages of the conversation
     * @return Generated title string (3-10 words)
     */
    @AuraEnabled
    public static String generateSessionTitle(String conversationContext) {
        try {
            // Validate input
            if (String.isBlank(conversationContext)) {
                return 'Untitled Conversation';
            }
            
            System.debug('Generating title for context: ' + conversationContext);
            
            // Prepare the prompt template input
            ConnectApi.EinsteinPromptTemplateGenerationsInput input = 
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            
            // Set the correct application name as per documentation
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            
            // Set input variables with Input: prefix as per documentation
            Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();
            ConnectApi.WrappedValue wrappedContext = new ConnectApi.WrappedValue();
            wrappedContext.value = conversationContext;
            // Use Input: prefix format
            valueMap.put('Input:conversationContext', wrappedContext);
            input.inputParams = valueMap;
            
            input.isPreview = false;
            
            System.debug('Calling prompt template: ' + PROMPT_TEMPLATE_NAME);
            
            // Call the Einstein Prompt Template API
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response = 
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_NAME, input);
            
            System.debug('Response received successfully');
            
            // Extract and return the generated title
            if (response != null && response.generations != null && !response.generations.isEmpty()) {
                String generatedTitle = response.generations[0].text;
                System.debug('Generated title: ' + generatedTitle);
                return String.isNotBlank(generatedTitle) ? generatedTitle.trim() : 'AI Generated Title';
            }
            
            System.debug('No generations in response');
            return 'Untitled Conversation';
            
        } catch (ConnectApi.ConnectApiException e) {
            System.debug(LoggingLevel.ERROR, 'ConnectApi Error generating title: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Error code: ' + e.getErrorCode());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            return 'Conversation Summary';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'General Error generating title: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Exception type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            return 'Conversation Summary';
        }
    }
    
    /**
     * @description Builds the SQL query for retrieving session data from Data Cloud
     * @param daysLookback Number of days to look back
     * @param userId Current user's Salesforce ID
     * @return SQL query string
     */
    private static String buildSessionQuery(Integer daysLookback, String userId) {
        // Sanitize inputs to prevent SQL injection
        String sanitizedUserId = String.escapeSingleQuotes(userId);
        
        // Build the query using your org's Data Cloud schema
        // Note: Using CTE to deduplicate agent names per session
        String query = 
            'WITH AgentNamesPerSession AS ( ' +
                'SELECT ' +
                    '"aiAgentSessionId__c", ' +
                    'MAX("aiAgentApiName__c") AS "AgentName" ' +
                'FROM "AiAgentSessionParticipant__dll" ' +
                'WHERE "aiAgentSessionParticipantRole__c" = \'AGENT\' ' +
                'GROUP BY "aiAgentSessionId__c" ' +
            ') ' +
            'SELECT ' +
                'm."aiAgentSessionId__c" AS "SessionId", ' +
                'an."AgentName", ' +
                's."startTimestamp__c" AS "StartTime", ' +
                'm."messageSentTimestamp__c" AS "MessageTime", ' +
                'p."aiAgentSessionParticipantRole__c" AS "Role", ' +
                'm."contentText__c" AS "MessageText" ' +
            'FROM "AiAgentInteractionMessage__dll" m ' +
            'JOIN "AiAgentSessionParticipant__dll" p ON m."aiAgentSessionParticipantId__c" = p."id__c" ' +
            'JOIN "AiAgentSession__dll" s ON m."aiAgentSessionId__c" = s."id__c" ' +
            'LEFT JOIN AgentNamesPerSession an ON s."id__c" = an."aiAgentSessionId__c" ' +
            'WHERE m."aiAgentSessionId__c" IN ( ' +
                'SELECT "aiAgentSessionId__c" ' +
                'FROM "AiAgentSessionParticipant__dll" ' +
                'WHERE "participantId__c" = \'' + sanitizedUserId + '\' ' +
            ') ' +
            'AND s."startTimestamp__c" >= CURRENT_DATE - INTERVAL \'' + daysLookback + '\' DAY ' +
            'ORDER BY "SessionId", "MessageTime" ASC ' +
            'LIMIT ' + MAX_ROWS_LIMIT;
        
        return query;
    }
    
    /**
     * @description Transforms flat SQL results into hierarchical SessionWrapper structure
     * @param queryOutput Results from Data Cloud query
     * @return List of SessionWrapper objects
     */
    private static List<SessionWrapper> transformQueryResults(ConnectApi.QuerySqlOutput queryOutput) {
        Map<String, SessionWrapper> sessionMap = new Map<String, SessionWrapper>();
        
        if (queryOutput == null || queryOutput.dataRows == null || queryOutput.dataRows.isEmpty()) {
            return new List<SessionWrapper>();
        }
        
        // Process each row from the query result
        for (ConnectApi.QuerySqlRow sqlRow : queryOutput.dataRows) {
            // Get the row data array
            Object[] rowData = sqlRow.row;
            
            if (rowData == null || rowData.isEmpty()) {
                continue;
            }
            
            // Extract fields by index based on SELECT order:
            // 0: SessionId, 1: AgentName, 2: StartTime, 3: MessageTime, 4: Role, 5: MessageText
            String sessionId = getStringValue(rowData, 0);
            
            if (String.isBlank(sessionId)) {
                continue;
            }
            
            // Get or create session wrapper (first row for this session has earliest message due to ORDER BY MessageTime ASC)
            if (!sessionMap.containsKey(sessionId)) {
                SessionWrapper session = new SessionWrapper();
                session.sessionId = sessionId;
                session.agentName = getStringValue(rowData, 1); // AgentName from CTE
                session.startTime = getDateTimeValue(rowData, 2); // StartTime from session table
                if (session.startTime == null) {
                    Long fromMsg = timestampStringToEpochMs(getStringValue(rowData, 3)); // MessageTime
                    if (fromMsg != null) session.startTime = DateTime.newInstance(fromMsg);
                }
                session.messages = new List<MessageWrapper>();
                session.title = 'Loading...'; // Default title
                sessionMap.put(sessionId, session);
            }
            
            SessionWrapper currentSession = sessionMap.get(sessionId);
            
            // Create message wrapper
            MessageWrapper message = new MessageWrapper();
            message.role = getStringValue(rowData, 4); // Role (USER or AGENT)
            message.text = getStringValue(rowData, 5); // MessageText
            message.timestamp = getStringValue(rowData, 3); // MessageTime
            
            // Only add non-empty messages
            if (String.isNotBlank(message.text)) {
                currentSession.messages.add(message);
            }
        }
        
        // Set startTime from first message when null, and set sortEpochMs from first message timestamp for all sessions
        for (SessionWrapper sw : sessionMap.values()) {
            Long firstMsgEpoch = getEpochFromFirstMessage(sw);
            if (sw.startTime == null && firstMsgEpoch != null) {
                sw.startTime = DateTime.newInstance(firstMsgEpoch);
            }
            if (sw.startTime != null) {
                sw.sortEpochMs = sw.startTime.getTime();
            } else {
                sw.sortEpochMs = firstMsgEpoch;
            }
        }
        
        // Build list from map (sort for home is done in sortSessionsNewestFirst)
        List<SessionWrapper> sessions = new List<SessionWrapper>(sessionMap.values());
        sessions.sort();
        
        return sessions;
    }
    
    /**
     * Get epoch milliseconds from session's first message timestamp (for sort). Tries multiple parse strategies.
     */
    private static Long getEpochFromFirstMessage(SessionWrapper sw) {
        if (sw.messages == null || sw.messages.isEmpty()) return null;
        String ts = sw.messages[0].timestamp;
        if (String.isBlank(ts)) return null;
        return timestampStringToEpochMs(ts);
    }
    
    /** Debug: log first/last session sort keys so logs show if sort is applied (Developer Console > Debug Logs). */
    @TestVisible
    private static void logSessionSortDiagnostics(String label, List<SessionWrapper> sessions) {
        if (sessions == null || sessions.isEmpty()) return;
        Long first = getSessionSortTimeEpoch(sessions[0]);
        Long last = getSessionSortTimeEpoch(sessions[sessions.size() - 1]);
        System.debug(LoggingLevel.INFO, 'AgentSessions_Home ' + label + ': count=' + sessions.size() + ' firstEpoch=' + first + ' lastEpoch=' + last + ' (newest first => first > last)');
    }
    
    /**
     * Convert timestamp string to epoch milliseconds. Tries multiple formats so Data Cloud timestamps parse.
     */
    @TestVisible
    private static Long timestampStringToEpochMs(String ts) {
        if (String.isBlank(ts)) return null;
        String s = ts.trim();
        if (s.length() == 0) return null;
        try {
            DateTime dt = DateTime.valueOfGmt(s);
            return dt.getTime();
        } catch (Exception e) { }
        try {
            String withSpace = s.replace('T', ' ');
            return DateTime.valueOfGmt(withSpace).getTime();
        } catch (Exception e) { }
        try {
            String t = s.replace(' ', 'T');
            return DateTime.valueOfGmt(t).getTime();
        } catch (Exception e) { }
        try {
            if (s.length() >= 19) return DateTime.valueOfGmt(s.substring(0, 19).replace('T', ' ')).getTime();
        } catch (Exception e) { }
        try {
            String noZ = s.replace('Z', ' ').trim();
            if (noZ.length() >= 19) return DateTime.valueOfGmt(noZ.substring(0, 19).replace('T', ' ')).getTime();
        } catch (Exception e) { }
        try {
            Integer dot = s.indexOf('.');
            if (dot > 18) return DateTime.valueOfGmt(s.substring(0, 19).replace('T', ' ')).getTime();
            if (dot > 0) {
                String withoutMs = s.substring(0, dot);
                if (withoutMs.length() >= 19) return DateTime.valueOfGmt(withoutMs.substring(0, 19).replace('T', ' ')).getTime();
                return DateTime.valueOfGmt(withoutMs.replace('T', ' ')).getTime();
            }
        } catch (Exception e) { }
        try {
            Long epoch = Long.valueOf(s);
            if (epoch > 0L) return epoch;
        } catch (Exception e) { }
        return null;
    }
    
    /**
     * Returns sessions in descending start time order (newest first) for pagination.
     * Selection sort: repeatedly take the session with max epoch and append to result (no add(index, element)).
     */
    @TestVisible
    private static List<SessionWrapper> sortSessionsNewestFirst(List<SessionWrapper> sessions) {
        if (sessions == null || sessions.isEmpty()) return new List<SessionWrapper>();
        if (sessions.size() == 1) return new List<SessionWrapper>(sessions);
        List<SessionWrapper> copy = new List<SessionWrapper>(sessions);
        List<SessionWrapper> result = new List<SessionWrapper>();
        while (!copy.isEmpty()) {
            Integer maxIdx = 0;
            Long maxEpoch = getSessionSortTimeEpoch(copy[0]);
            for (Integer i = 1; i < copy.size(); i++) {
                Long epoch = getSessionSortTimeEpoch(copy[i]);
                if (epoch != null && (maxEpoch == null || epoch > maxEpoch)) {
                    maxEpoch = epoch;
                    maxIdx = i;
                }
            }
            result.add(copy[maxIdx]);
            copy.remove(maxIdx);
        }
        return result;
    }
    
    /** Epoch milliseconds for sort (newest = larger). Uses sortEpochMs set in transformQueryResults. */
    private static Long getSessionSortTimeEpoch(SessionWrapper sw) {
        if (sw.sortEpochMs != null) return sw.sortEpochMs;
        DateTime dt = getSessionSortTime(sw);
        if (dt != null) return dt.getTime();
        return 0L;
    }
    
    /** Sort time for a session: startTime, or first message timestamp, or null. */
    private static DateTime getSessionSortTime(SessionWrapper sw) {
        if (sw.startTime != null) return sw.startTime;
        if (sw.messages != null && !sw.messages.isEmpty()) {
            return parseMessageTimestamp(sw.messages[0].timestamp);
        }
        return null;
    }
    
    /**
     * Parse message timestamp string from Data Cloud (handles ISO and space-separated formats).
     * Data Cloud timestamps are in UTC, so we parse as GMT.
     */
    private static DateTime parseMessageTimestamp(String ts) {
        if (String.isBlank(ts)) return null;
        String s = ts.trim();
        try {
            return DateTime.valueOfGmt(s);
        } catch (Exception e) { }
        try {
            String normalized = s.replace(' ', 'T');
            if (normalized.length() > 19 && normalized.indexOf('Z') == -1 && normalized.indexOf('+') == -1 && normalized.indexOf('-', 10) == -1) {
                normalized = normalized.substring(0, 19);
            }
            return DateTime.valueOfGmt(normalized);
        } catch (Exception e) { }
        try {
            if (s.length() >= 19) return DateTime.valueOfGmt(s.substring(0, 19).replace(' ', 'T'));
        } catch (Exception e) { }
        return null;
    }
    
    /**
     * @description Helper method to safely extract string values from row data array
     * @param rowData Array of row values
     * @param index Index of the value to extract
     * @return String value or empty string if not found
     */
    private static String getStringValue(Object[] rowData, Integer index) {
        try {
            if (rowData == null || index >= rowData.size() || rowData[index] == null) {
                return '';
            }
            return String.valueOf(rowData[index]);
        } catch (Exception e) {
            return '';
        }
    }
    
    /**
     * @description Helper method to extract DateTime values from row data array
     * Data Cloud timestamps are in UTC, so we parse them as GMT.
     * @param rowData Array of row values
     * @param index Index of the value to extract
     * @return DateTime value or null if not found
     */
    private static DateTime getDateTimeValue(Object[] rowData, Integer index) {
        try {
            String dateStr = getStringValue(rowData, index);
            if (String.isNotBlank(dateStr)) {
                // Data Cloud returns timestamps in UTC without timezone indicator
                // Use valueOfGmt to parse as UTC instead of user's timezone
                return DateTime.valueOfGmt(dateStr);
            }
        } catch (Exception e) {
            System.debug('Error parsing DateTime: ' + e.getMessage());
        }
        return null;
    }
    
    /**
     * @description Wrapper class for session data
     */
    public class SessionWrapper implements Comparable {
        @AuraEnabled public String sessionId;
        @AuraEnabled public String agentName;
        @AuraEnabled public DateTime startTime;
        @AuraEnabled public String title;
        @AuraEnabled public List<MessageWrapper> messages;
        /** Epoch ms from first message (or startTime) for descending sort; set in transformQueryResults. */
        public Long sortEpochMs;
        
        /**
         * @description Comparator to sort sessions by start time (most recent first)
         */
        public Integer compareTo(Object other) {
            SessionWrapper otherSession = (SessionWrapper) other;
            if (this.startTime == null && otherSession.startTime == null) return 0;
            if (this.startTime == null) return 1;
            if (otherSession.startTime == null) return -1;
            
            // Sort descending (most recent first)
            return otherSession.startTime > this.startTime ? 1 : -1;
        }
    }
    
    /**
     * @description Wrapper class for individual messages
     */
    public class MessageWrapper {
        @AuraEnabled public String role;
        @AuraEnabled public String text;
        @AuraEnabled public String timestamp;
    }

    /**
     * @description Wrapper for paginated session results (home tab component)
     */
    public class PaginatedSessionsWrapper {
        @AuraEnabled public List<SessionWrapper> sessions;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public String userTimeZone;
        public PaginatedSessionsWrapper(List<SessionWrapper> sessions, Integer totalCount) {
            this.sessions = sessions;
            this.totalCount = totalCount;
            this.userTimeZone = null;
        }
        public PaginatedSessionsWrapper(List<SessionWrapper> sessions, Integer totalCount, String userTimeZone) {
            this.sessions = sessions;
            this.totalCount = totalCount;
            this.userTimeZone = userTimeZone;
        }
    }
}
