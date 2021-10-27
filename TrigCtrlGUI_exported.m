classdef TrigCtrlGUI_exported < handle %matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        BolusTriggerCtrlUIFigure    matlab.ui.Figure
        BOLUSButton                 matlab.ui.control.Button
        sendcustomtriggerButton     matlab.ui.control.Button
        Label                       matlab.ui.control.Label
        TrgNumEditField             matlab.ui.control.NumericEditField
        NumberAuroraLabel           matlab.ui.control.Label
        DurationPhysioMonitorLabel  matlab.ui.control.Label
        secondsEditFieldLabel       matlab.ui.control.Label
        TrgDurationEditField        matlab.ui.control.NumericEditField
    end

    
    % PROPERTIES ==========================================================
    properties (Access = public)
        nrisDataTrg = [] % 2-elemnt with time and trigger#: [secondsOfDay, trgNumber]
        bolusPrepDelay = 10; % delay between 1st trigger and actual bolus release in seconds
        bolusTrgNums = [49 50 51];
        bolusTrgDuration = 8; % duration for setting injector-trigger to high...
        % CAVE: if too short injection will be aborted?!
        logPath = fullfile(userpath,'TriggerCtrlGUI','logs');
        logFile
        lsloutlet
        scomObj % Description
    end
    
    properties (Access = private)
        iON  = 'a';
        iOFF = 'b';
        pON  = 'x';
        pOFF = 'y';
    end
    
    % METHODS =============================================================
    methods (Access = private)
        
        function setNSPdataTrg(app,value)
            % OBSOLETE
            % sets object property with current time and trg value
            value = fix(value);
            t = rem(now,1)*24*60*60;
            app.nrisDataTrg = [app.nrisDataTrg; [t, value]];
        end
        % .................................................................
        
        function sendLSLtrg(app,val)
            app.lsloutlet.push_sample(val);
        end
        % .................................................................
        
        function sendNIRStrg_(app, value)
            sendLSLtrg(app,value)
            % workaround for lsl-induced aurora crash:
%             setNSPdataTrg(app,value);
        end
        % .................................................................
        
        function sendPhysioTrg_(app,duration)
            l = write2com(app,app.pON);
            pause(duration);
            l = write2com(app,app.pOFF);
        end
        % .................................................................
        
        function sendBolusAndPhysioTrg_(app)
            sendNIRStrg_(app,app.bolusTrgNums(1));
            fprintf('%s (TCG): Bolus will be released in %.1f seconds...\n', ...
                        datestr(now,'yyyy-mm-dd HH:MM:SS'), app.bolusPrepDelay);
            pause(app.bolusPrepDelay);
            
            sendNIRStrg_(app,app.bolusTrgNums(2));
            l = write2com(app,[app.iON app.pON]);
            writeLog(app,'Bolus released.');
            fprintf('%s (TCG): Bolus released. Trigger will be low in %.1f seconds...\n', ...
                        datestr(now,'yyyy-mm-dd HH:MM:SS'), app.bolusTrgDuration);
            pause(app.bolusTrgDuration);
            
            sendNIRStrg_(app,app.bolusTrgNums(3));
            l = write2com(app,[app.iOFF app.pOFF]);
            writeLog(app,'Bolus trigger low.');
        end
        % .................................................................
    end
    
    methods (Access = public)
        
        function sendNIRStrg(app, value)
            writeLog(app,'Triggering NIRS.')
            sendNIRStrg_(app,value);
        end
        % .................................................................

        function sendPhysioTrg(app,duration)
            writeLog(app,'Triggering Physio.');
            sendPhysioTrg_(app,duration);
        end
        % .................................................................

        function sendNIRSandPhysioTrg(app,value,duration)
            writeLog(app,'Triggering NIRS and Physio.');
            sendNIRStrg_(app,value);
            sendPhysioTrg_(app,duration);
        end
        % .................................................................
        
        function sendBolusAndPhysioTrg(app)
            writeLog(app,'Triggering bolus: NIRS data, physio, injector.');
            sendBolusAndPhysioTrg_(app);
        end
        % .................................................................
        
        function latency = write2com(app,buf)
%             latency = 0;
%             warning('!!! Triggerbox DISABELED !!!')
%             return; % <<<<<<<<<<<<<< DEBUG <<<<<<<<<<<<<<<<<
            t = tic;
            write(app.scomObj,buf,'char'); %uint8
            while app.scomObj.NumBytesAvailable<1
                if toc(t) > 2
                    errordlg('No receipt received!')
                    app.writeLog('ERROR: No receipt from trigger box received within 2 seconds.')
                    break;
                end
            end
            latency = toc(t);
            app.writeLog('Latency was %f seconds',latency);
%             AnzBytes=app.scomObj.NumBytesAvailable;
%             Data=read(app.scomObj,AnzBytes,'char')
        end
        % .................................................................
        
        function writeLog(app,msg,varargin)
            if ~isempty(varargin)
                msg = sprintf(msg,varargin{:});
            end
            fid = fopen(app.logFile,'a');
            fprintf(fid,'%s: %s\n',datestr(now,'yy-mm-dd HH:MM:SS'), msg);
            fclose(fid);
        end
        % .................................................................
    end
    

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function init_gui(app, lsloutlet, trgboxCOM)
            try app.scomObj = serialport(trgboxCOM,38400);
            catch ME
                errordlg('Failed to create serialport object!');
                warning('Failed to create serialport object!');
            end
%             write2com(app,[app.iOFF app.pOFF]);
            if ~exist(app.logPath,'dir'), mkdir(app.logPath); end
            app.logFile = fullfile(app.logPath,sprintf('%s.txt',datestr(now,'yyyymmdd')));
            app.lsloutlet = lsloutlet;
        end

        % Button pushed function: BOLUSButton
        function bolus_init(app, event)
            answer = inputdlg({'Delay in seconds:'},'Trigger BOLUS',[1,35],{'0'});
            if isempty(answer)
                return;
            else
                tdelay = str2num(answer{1});
                if ~isempty(tdelay) && isfinite(tdelay)
                    fprintf('%s (TCG): Waiting for %d seconds before bolus init...\n', ...
                        datestr(now,'yyyy-mm-dd HH:MM:SS'), tdelay(1));
                    pause(tdelay(1));
                else
                    warndlg('Failed to interpret entered delay! Bolus wont be initiated.');
                    return;
                end
            end
            sendBolusAndPhysioTrg(app);
        end

        % Button pushed function: sendcustomtriggerButton
        function sendCustomTrg(app, event)
            nirsTrgNum = app.TrgNumEditField.Value;
            physTrgDur = app.TrgDurationEditField.Value;
            if nirsTrgNum>0 && physTrgDur>0
                msg = sprintf('Sending trigger %d to NIRS and setting Physio-Trigger to high for %.1f seconds.',nirsTrgNum,physTrgDur);
                fncHndl = @()app.sendNIRSandPhysioTrg(nirsTrgNum,physTrgDur);
            elseif nirsTrgNum>0
                msg = sprintf('Sending trigger %d to NIRS.',nirsTrgNum);
                fncHndl = @()app.sendNIRStrg(nirsTrgNum);
            elseif physTrgDur>0
                msg = sprintf('Setting Physio-Trigger to high for %.1f seconds.',physTrgDur);
                fncHndl = @()app.sendPhysioTrg(physTrgDur);
            else
                msgbox('No trigger to send.');
                return;
            end
            answer = uiconfirm(app.BolusTriggerCtrlUIFigure, ...
                msg, 'Confirm custom trigger');
            if strcmpi(answer,'ok')
                fncHndl();
            end
        end

        % Close request function: BolusTriggerCtrlUIFigure
        function figDestructor(app, event)
%             fclose(app.logfid)
            delete(app)
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create BolusTriggerCtrlUIFigure and hide until all components are created
            app.BolusTriggerCtrlUIFigure = uifigure('Visible', 'off');
            app.BolusTriggerCtrlUIFigure.Position = [100 100 336 221];
            app.BolusTriggerCtrlUIFigure.Name = 'BolusTriggerCtrl';
%             app.BolusTriggerCtrlUIFigure.CloseRequestFcn = @figDestructor;%createCallbackFcn(app, @figDestructor, true);

            % Create BOLUSButton
            app.BOLUSButton = uibutton(app.BolusTriggerCtrlUIFigure, 'push');
            app.BOLUSButton.ButtonPushedFcn = @(~,~)bolus_init(app,0);%   createCallbackFcn(app, @bolus_init, true);
            app.BOLUSButton.BackgroundColor = [0.851 0.3255 0.098];
            app.BOLUSButton.FontSize = 20;
            app.BOLUSButton.FontWeight = 'bold';
            app.BOLUSButton.Position = [51 141 236 70];
            app.BOLUSButton.Text = 'BOLUS';

            % Create sendcustomtriggerButton
            app.sendcustomtriggerButton = uibutton(app.BolusTriggerCtrlUIFigure, 'push');
            app.sendcustomtriggerButton.ButtonPushedFcn = @(~,~)sendCustomTrg(app,0);%   createCallbackFcn(app, @sendCustomTrg, true);
            app.sendcustomtriggerButton.Position = [51 72 236 22];
            app.sendcustomtriggerButton.Text = 'send custom trigger:';

            % Create Label
            app.Label = uilabel(app.BolusTriggerCtrlUIFigure);
            app.Label.HorizontalAlignment = 'right';
            app.Label.Position = [248 43 39 22];
            app.Label.Text = '[1-255]';

            % Create TrgNumEditField
            app.TrgNumEditField = uieditfield(app.BolusTriggerCtrlUIFigure, 'numeric');
            app.TrgNumEditField.Position = [197 44 43 21];

            % Create NumberAuroraLabel
            app.NumberAuroraLabel = uilabel(app.BolusTriggerCtrlUIFigure);
            app.NumberAuroraLabel.Position = [51 43 109 22];
            app.NumberAuroraLabel.Text = 'Number (Aurora):';

            % Create DurationPhysioMonitorLabel
            app.DurationPhysioMonitorLabel = uilabel(app.BolusTriggerCtrlUIFigure);
            app.DurationPhysioMonitorLabel.Position = [51 16 142 22];
            app.DurationPhysioMonitorLabel.Text = 'Duration (PhysioMonitor):';

            % Create secondsEditFieldLabel
            app.secondsEditFieldLabel = uilabel(app.BolusTriggerCtrlUIFigure);
            app.secondsEditFieldLabel.HorizontalAlignment = 'right';
            app.secondsEditFieldLabel.Position = [233 16 54 22];
            app.secondsEditFieldLabel.Text = ' seconds';

            % Create TrgDurationEditField
            app.TrgDurationEditField = uieditfield(app.BolusTriggerCtrlUIFigure, 'numeric');
            app.TrgDurationEditField.Position = [197 17 37 21];

            % Show the figure after all components are created
            app.BolusTriggerCtrlUIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = TrigCtrlGUI_exported(varargin)

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
%             registerApp(app, app.BolusTriggerCtrlUIFigure)

            % Execute the startup function
            init_gui(app,varargin{:});
%             runStartupFcn(app, @(app)init_gui(app, varargin{:}))

            if nargout == 0
%                 clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.BolusTriggerCtrlUIFigure)
        end
    end
end