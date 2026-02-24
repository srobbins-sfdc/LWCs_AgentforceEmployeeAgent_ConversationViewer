import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getUserSessions from '@salesforce/apex/AgentGPTController.getUserSessions';
import getCurrentUserTimeZone from '@salesforce/apex/AgentGPTController.getCurrentUserTimeZone';
import generateSessionTitle from '@salesforce/apex/AgentGPTController.generateSessionTitle';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { renderMessageContent } from 'c/messageFormatter';
import loadingIconUrl from '@salesforce/resourceUrl/LWCLoadingIcon';
import agentAstroUrl from '@salesforce/resourceUrl/AgentAstro';

export default class AgentGPT extends LightningElement {
    @track sessions = [];
    @track selectedSession = null;
    @track dateFilter = 7;
    @track isLoading = true;
    /** User timezone from Salesforce for consistent date/time display (matches Data Cloud expectation). */
    userTimeZone = null;

    wiredSessionsResult;

    @wire(getCurrentUserTimeZone)
    wiredTimeZone({ data }) {
        if (data) {
            this.userTimeZone = data;
            // Re-format session dates and message times when timezone arrives (wire may complete after getUserSessions)
            if (this.sessions && this.sessions.length > 0) {
                this.sessions = this.sessions.map(s => ({
                    ...s,
                    formattedDate: this.formatDate(s.startTime),
                    messages: (s.messages || []).map(msg => ({
                        ...msg,
                        formattedTime: this.formatTime(msg.timestamp)
                    }))
                }));
            }
        }
    }

    get loadingIconSrc() {
        return loadingIconUrl;
    }

    get agentAstroSrc() {
        return agentAstroUrl;
    }

    /**
     * Wire service to fetch user sessions
     */
    @wire(getUserSessions, { daysLookback: '$dateFilter' })
    wiredSessions(result) {
        this.wiredSessionsResult = result;
        const { data, error } = result;
        
        if (data) {
            console.log('Raw session data:', JSON.stringify(data));
            // Process sessions and format dates
            this.sessions = data.map(session => {
                // Use startTime if available, otherwise use first message timestamp
                const sessionStartTime = session.startTime || 
                    (session.messages && session.messages.length > 0 ? session.messages[0].timestamp : null);
                
                return {
                    ...session,
                    startTime: sessionStartTime,
                    formattedDate: this.formatDate(sessionStartTime),
                    messages: this.processMessages(session.messages),
                    cssClass: 'session-item'
                };
            });
            
            this.isLoading = false;
            
            // Generate titles for sessions that need them
            this.generateMissingTitles();
        } else if (error) {
            console.error('Error loading sessions:', error);
            this.showError('Error loading conversations: ' + this.reduceErrors(error));
            this.sessions = [];
            this.isLoading = false;
        }
    }

    /**
     * Generate titles for sessions that don't have them
     */
    async generateMissingTitles() {
        const sessionsNeedingTitles = this.sessions.filter(s => 
            s.title === 'Loading...' && s.messages && s.messages.length > 0
        );

        // Sort by startTime descending (newest first)
        sessionsNeedingTitles.sort((a, b) => {
            const dateA = new Date(a.startTime);
            const dateB = new Date(b.startTime);
            return dateB - dateA;
        });

        for (const session of sessionsNeedingTitles) {
            try {
                await this.generateTitleForSession(session);
            } catch (error) {
                console.error(`Failed to generate title for session ${session.sessionId}:`, error);
                session.title = 'Untitled Conversation';
            }
        }
    }

    /**
     * Generate title for a specific session
     */
    async generateTitleForSession(session) {
        try {
            // Get first 3 messages for context
            const contextMessages = session.messages.slice(0, 3);
            const conversationContext = contextMessages
                .map(msg => `${msg.roleLabel}: ${msg.text}`)
                .join('\n');

            console.log('Generating title with context:', conversationContext);

            // Call Apex to generate title
            const generatedTitle = await generateSessionTitle({ 
                conversationContext 
            });

            console.log('Generated title:', generatedTitle);

            if (generatedTitle && generatedTitle !== 'Loading...') {
                // Update session title
                const sessionIndex = this.sessions.findIndex(s => s.sessionId === session.sessionId);
                if (sessionIndex !== -1) {
                    this.sessions[sessionIndex].title = generatedTitle;
                    
                    // Force UI refresh
                    this.sessions = [...this.sessions];
                    
                    // Update selected session if it's the current one
                    if (this.selectedSession && this.selectedSession.sessionId === session.sessionId) {
                        this.selectedSession = { ...this.sessions[sessionIndex] };
                    }
                }
            }
        } catch (error) {
            console.error('Error in generateTitleForSession:', error);
            throw error;
        }
    }

    /**
     * Group sessions by date for sidebar display
     */
    get groupedSessions() {
        const today = new Date();
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);

        // Dynamic label based on date filter
        const previousLabel = this.dateFilter === 90 ? 'Previous 90 Days' : 
                             this.dateFilter === 30 ? 'Previous 30 Days' : 
                             'Previous 7 Days';

        const groups = {
            today: { label: 'Today', icon: 'utility:clock', sessions: [] },
            yesterday: { label: 'Yesterday', icon: 'utility:history', sessions: [] },
            previous: { label: previousLabel, icon: 'utility:date_input', sessions: [] }
        };

        this.sessions.forEach(session => {
            // Ensure formattedDate is set
            const formattedDate = session.formattedDate || this.formatDate(session.startTime);
            
            const sessionDate = new Date(session.startTime);
            const sessionCopy = {
                ...session,
                formattedDate: formattedDate,
                cssClass: this.selectedSession && this.selectedSession.sessionId === session.sessionId 
                    ? 'session-item selected' 
                    : 'session-item'
            };

            if (this.isSameDay(sessionDate, today)) {
                groups.today.sessions.push(sessionCopy);
            } else if (this.isSameDay(sessionDate, yesterday)) {
                groups.yesterday.sessions.push(sessionCopy);
            } else {
                groups.previous.sessions.push(sessionCopy);
            }
        });

        // Sort sessions within each group (most recent first)
        Object.values(groups).forEach(group => {
            group.sessions.sort((a, b) => {
                const dateA = new Date(a.startTime);
                const dateB = new Date(b.startTime);
                return dateB - dateA; // Descending order (newest first)
            });
        });

        // Return only groups that have sessions
        return Object.values(groups).filter(group => group.sessions.length > 0);
    }

    /**
     * Computed property: Check if sessions exist
     */
    get hasSessions() {
        return this.sessions && this.sessions.length > 0;
    }

    /**
     * Computed property: Check if a session is selected
     */
    get hasSelectedSession() {
        return this.selectedSession !== null;
    }

    /**
     * Computed property: Check if selected session has messages
     */
    get hasMessages() {
        return this.selectedSession && 
               this.selectedSession.messages && 
               this.selectedSession.messages.length > 0;
    }

    /**
     * Date filter checks
     */
    get isSevenDays() {
        return this.dateFilter === 7;
    }

    get isThirtyDays() {
        return this.dateFilter === 30;
    }

    get isNinetyDays() {
        return this.dateFilter === 90;
    }

    /**
     * Handle filter change event
     */
    handleFilterChange(event) {
        this.dateFilter = parseInt(event.detail.value, 10);
        this.isLoading = true;
        this.selectedSession = null;
        
        // Refresh the wire service
        return refreshApex(this.wiredSessionsResult);
    }

    /**
     * Handle session selection
     */
    handleSessionSelect(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        const session = this.sessions.find(s => s.sessionId === sessionId);
        
        if (session) {
            // Process messages with agent name context
            const sessionWithProcessedMessages = {
                ...session,
                messages: this.processMessagesWithAgent(session.messages, session.agentName)
            };
            this.selectedSession = sessionWithProcessedMessages;
            
            // Scroll to top of messages
            this.scrollToTop();
        }
    }

    /**
     * Handle back to list
     */
    handleBackToList(event) {
        event.preventDefault();
        this.selectedSession = null;
    }

    /**
     * Process messages to add formatted data
     */
    processMessages(messages) {
        if (!messages) return [];
        
        return messages.map(msg => {
            const role = msg.role ? msg.role.toUpperCase() : '';
            const isUser = role === 'USER' || role === 'ENDUSER';
            return {
                ...msg,
                roleLabel: this.getRoleLabel(role, null),
                formattedTime: this.formatTime(msg.timestamp),
                isUser: isUser,
                cssClass: isUser ? 'message user-message' : 'message agent-message',
                renderedContent: renderMessageContent(msg.text)
            };
        });
    }

    /**
     * Process messages with agent name context for display
     */
    processMessagesWithAgent(messages, agentName) {
        if (!messages) return [];
        
        return messages.map(msg => {
            const role = msg.role ? msg.role.toUpperCase() : '';
            const isUser = role === 'USER' || role === 'ENDUSER';
            return {
                ...msg,
                roleLabel: this.getRoleLabel(role, agentName),
                formattedTime: this.formatTime(msg.timestamp),
                isUser: isUser,
                cssClass: isUser ? 'message user-message' : 'message agent-message',
                renderedContent: renderMessageContent(msg.text)
            };
        });
    }

    /**
     * Get human-readable role label
     */
    getRoleLabel(role, agentName) {
        const upperRole = role.toUpperCase();
        if (upperRole === 'USER' || upperRole === 'ENDUSER') {
            return 'You';
        } else if (upperRole === 'AGENT' || upperRole === 'SYSTEM') {
            return agentName || 'Agentforce AI';
        }
        return role;
    }

    /**
     * Format date for display (uses Salesforce user timezone when available).
     */
    formatDate(dateTimeString) {
        if (!dateTimeString) return '';
        try {
            const date = new Date(dateTimeString);
            const today = new Date();
            const yesterday = new Date(today);
            yesterday.setDate(yesterday.getDate() - 1);
            const opts = this.userTimeZone ? { timeZone: this.userTimeZone } : {};
            if (this.isSameDay(date, today)) return 'Today';
            if (this.isSameDay(date, yesterday)) return 'Yesterday';
            const showYear = this.userTimeZone
                ? date.toLocaleDateString('en-CA', { ...opts, year: 'numeric' }) !== today.toLocaleDateString('en-CA', { ...opts, year: 'numeric' })
                : date.getFullYear() !== today.getFullYear();
            return date.toLocaleDateString('en-US', {
                ...opts,
                month: 'short',
                day: 'numeric',
                year: showYear ? 'numeric' : undefined
            });
        } catch (e) {
            return dateTimeString;
        }
    }

    /**
     * Format time for display (uses Salesforce user timezone when available).
     */
    formatTime(timestamp) {
        if (!timestamp) return '';
        try {
            const date = new Date(timestamp);
            const opts = this.userTimeZone ? { timeZone: this.userTimeZone } : {};
            return date.toLocaleTimeString('en-US', {
                ...opts,
                month: 'short',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            });
        } catch (e) {
            return timestamp;
        }
    }

    /**
     * Check if two dates are the same day (in user timezone when set).
     */
    isSameDay(date1, date2) {
        if (!date1 || !date2 || isNaN(date1.getTime()) || isNaN(date2.getTime())) return false;
        if (this.userTimeZone) {
            const opts = { timeZone: this.userTimeZone };
            return date1.toLocaleDateString('en-CA', opts) === date2.toLocaleDateString('en-CA', opts);
        }
        return date1.getDate() === date2.getDate() &&
               date1.getMonth() === date2.getMonth() &&
               date1.getFullYear() === date2.getFullYear();
    }

    /**
     * Scroll messages to top
     */
    scrollToTop() {
        setTimeout(() => {
            const container = this.template.querySelector('.messages-container');
            if (container) {
                container.scrollTop = 0;
            }
        }, 100);
    }

    /**
     * Show error toast
     */
    showError(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: message,
                variant: 'error'
            })
        );
    }

    /**
     * Reduce errors to string
     */
    reduceErrors(errors) {
        if (!errors) {
            return 'Unknown error';
        }
        
        if (Array.isArray(errors)) {
            return errors
                .filter(error => !!error)
                .map(error => {
                    if (error.message) {
                        return error.message;
                    }
                    return error.statusText || error.body?.message || 'Unknown error';
                })
                .join(', ');
        }
        
        if (typeof errors === 'string') {
            return errors;
        }
        
        if (errors.body) {
            if (errors.body.message) {
                return errors.body.message;
            }
            if (errors.body.pageErrors && errors.body.pageErrors.length) {
                return errors.body.pageErrors[0].message;
            }
        }
        
        return errors.message || errors.statusText || 'Unknown error';
    }
}
