% TOGGLETOOLBOX              Utility to enable/disable MATLAB toolboxes.
%
% S = TOGGLETOOLBOX()
% S = TOGGLETOOLBOX('')
% S = TOGGLETOOLBOX('all') queries the on/off states of all installed
% toolboxes.
%
% M = TOGGLETOOLBOX('names') returns the full names / directory names map
% [M] applicable to the current MATLAB installation.
%
% S = TOGGLETOOLBOX(toolbox, state) queries or sets the on/off state of the
% MATLAB toolbox [toolbox] to [state]. The string or cellstring [toolbox] may
% be equal to the toolbox' installation directory name (the same as used by
% ver()), or the toolbox' full name. The string [state] may be one of 'on',
% 'enable' (equivalent), 'off' or 'disable (equivalent), or 'query'. The
% return argument [S] is a structure containing the toolbox name(s) as
% fields, with the on/off state represented as true/false, and the MATLAB
% path as it was before the call.
%
% S = TOGGLETOOLBOX(..., permanency) for string [permanency] equal to
% 'permanent' will attempt to make the change persist between different
% MATLAB sessions. For [permanency] equal to 'temporary' (the default), the
% change will only last for the remainder of the current session.
%
% TOGGLETOOLBOX(S0) will reset the on/off states of all toolboxes to the
% states contained in [S0], where [S0] is a structure previously returned by
% TOGGLETOOLBOX() as outlined above.
%
% Disabling a toolbox is done by removing the relevant directories from the
% MATLAB path. Since the order of the path is important for name resolution,
% TOGGLETOOLBOX() attempts to keep the order of all paths as close to MATLAB's
% startup path as possible. Calling TOGGLETOOLBOX() multiple times for different
% toolboxes and arbitrary on/off states should not affect the overall path
% order -- calling TOGGLETOOLBOX('all', 'on') afterwards results in a path
% identical to the startup path.
%
% Note that TOGGLETOOLBOX() generates a MAT file for both performance and
% permanence between MATLAB sessions. Please make sure that TOGGLETOOLBOX()
% is located in a directory with write access.
%
%
% EXAMPLE SESSION:
%
%     >> M = toggleToolbox('names')%
%     M =
%         'aero'             'Aerospace Toolbox'
%         'aeroblks'         'Aerospace Blockset'
%         'bioinfo'          'Bioinformatics Toolbox'
%         'comm'             'Communications Toolbox'
%         ...
%
%    >> S = toggleToolbox({'Aerospace Toolbox' 'Wavelet Toolbox'}, 'query')
%    S =
%           aero: 1
%        wavelet: 1
%
%    >> w = ver('wavelet')
%    w =
%           Name: 'Wavelet Toolbox'
%        Version: '4.5'
%        Release: '(R2010a)'
%           Date: '25-Jan-2010'
%
%    >> S = toggleToolbox({'Aerospace Toolbox' 'Wavelet Toolbox'}, 'off');
%    >> toggleToolbox({'Aerospace Toolbox' 'Wavelet Toolbox'}, 'query')
%    ans =
%           aero: 0
%        wavelet: 0
%
%    >> w = ver('wavelet')
%    w =
%    0x0 struct array with fields:
%        Name
%        Version
%        Release
%        Date
%
%    >> toggleToolbox(S);
%    >> toggleToolbox({'Aerospace Toolbox' 'Wavelet Toolbox'}, 'query')
%    ans =
%           aero: 1
%        wavelet: 1
%
%    >> % Cross-platform developer mode:
%    >> S = toggleToolbox('all', 'off');
%
% See also ver, verLessThan, matlabroot, warning.
function varargout = toggleToolbox(varargin)

    %% Initialize
    % ====================================================

    % Default msg ID for error/warning messages
    msgId = mfilename();

    % Store toolbox states in a store file
    storefile = fullfile(fileparts(mfilename('fullpath')), ...
                         'toolbox_states.mat');


    % Names should be given as directory names, but who on Earth
    % knows those by heart? Therefore, we create a dirname/fullname
    % map, to allow users to enter the full toolbox name as well
    tb_name_map = get_tb_name_map();


    % Parse and check arguments to determine mode of operation
    restoremode = false;
    querymode   = false;

    toolbox   = 'all';
    state     = 'on';
    permanent = 'temporary';

    switch nargin
        case 0
            % return states of ALL toolboxes
            querymode = true;

        case 1

            % Reset states
            if isstruct(varargin{1})

                restoremode = true;
                state       = 'restore';

                toolbox_states = varargin{1};

                assert(nargout == 0,...
                      [msgId ':argoutcount_error'], ...
                      '%s for single input argument does not have any output arguments.',...
                      mfilename);

                assert(isfield(toolbox_states, 'path') && ...
                       all(isfield(toolbox_states, tb_name_map(:,1))),...
                       [msgId ':invalid_tbstates_structure'], ...
                       'Input argument does not appear to be a structure generated by %s.',...
                       mfilename);

            % Query state of single toolbox
            elseif ischar(varargin{1})

                % Return toolbox names map
                if strcmpi(varargin{1}, 'names')
                    varargout{1} = tb_name_map;
                    return;

                % query mode
                else
                    querymode = true;
                    toolbox   = varargin{1};
                    state     = 'query';
                end
            end

        case {2,3}
            % Toggle state of one or more toolboxes
            toolbox   = varargin{1};
            state     = varargin{2};
            querymode = strcmpi(state, 'query');
            
            if nargin == 3
                if ~querymode
                    permanent = varargin{3};
                else
                    warning([msgId ':permanence_na_in_querymode'],...
                            'Permanency flag ignored for ''query'' mode.');
                end
            end

        otherwise
            error([msgId ':argincount_error'],...
                  'Too many input arguments.');
    end

    % Cellstring of all paths makes for easier work
    paths = regexp(path, pathsep, 'split');

    % Initialize tb states structure
    if ~restoremode
        % Load previous paths and toggle states, if any
        toolbox_states = getpref('toggleToolbox___',...            
                                 'toolbox_states',...
                                 []);
        if isempty(toolbox_states)
            % Initialize it by storing the previous path strings...
            toolbox_states = struct('path', {paths});

            % ...and mark all toolboxes as "enabled"
            for ii = 1:size(tb_name_map,1)
                toolbox_states.(tb_name_map{ii,1}) = true; end
        end
    end

    % Some asserts
    assert(iscellstr(toolbox) || ischar(toolbox),...
           [msgId ':argument_error'], [...
           'Toolboxes must be given as a string (single toolbox) or a cell array of ',...
           'strings (multiple toolboxes).']);

    if ~restoremode
        assert(ischar(state) && any(strcmpi(state, {'on' 'enable' 'off' 'disable' 'query'})),...
               [msgId ':argument_error'],...
               'State must be a string equal to ''on''/''enable'', ''off''/''disable'', or ''query''.');
    end

    assert(ischar(permanent) && any(strcmpi(permanent, {'permanent', 'temporary'})),...
           [msgId ':argument_error'],...
           'Permanency must be indicated via string ''perpanent'' or ''temporary''.');


    % Apply name map
    if isempty(toolbox) || any(strcmpi(toolbox, 'all'))
        toolbox = tb_name_map(:,1);

    else
        if ~iscell(toolbox)
            toolbox = {toolbox}; end

        % Check names and perform lookups
        tb_name_map_i = cellfun(@lower, tb_name_map, 'UniformOutput', false);
        toolbox_i     = cellfun(@lower, toolbox,     'UniformOutput', false);

        dirs           = ismember(toolbox_i, tb_name_map_i(:,1));
        [isname,names] = ismember(toolbox_i, tb_name_map_i(:,2));

        assert(all(dirs | isname),...
               [msgId ':unknown_toolbox'],...
               'Toolbox: ''%s'' does not seem to be installed.',...
               toolbox{find( ~(dirs | isname), 1, 'first')});

        toolbox(isname) = tb_name_map(names(isname),1);
    end


    % Query mode: return current toggle states
    if querymode
        % ALL toolboxes
        if isempty(toolbox)
            setpref('toggleToolbox___',...
                    'toolbox_states',...
                    toolbox_states);
            varargout{1}   = toolbox_states;

        % SOME toolboxes
        else
            for ii = 1:numel(toolbox)
                toolbox_state.(toolbox{ii}) = toolbox_states.(toolbox{ii}); end
            varargout{1} = toolbox_state;
        end
        return;
    end


    %% Toggle all requested toolboxes
    % ====================================================

    toolbox_states_out = toolbox_states;

    switch lower(state)

        case {'off' 'disable'}
            
            % NOTE (Rody Oldenhuis): make sure the 'MATLAB' "toolbox"
            % is excluded, otherwise, MATLAB becomed unusable      
            toolbox(strcmpi(toolbox, 'MATLAB')) = [];
            if isempty(toolbox)
                warning([msgId ':matlab_toolbox_must_stay'],...
                        'The ''MATLAB'' toolbox can not be disabled.');
                return;
            end
            
            % Walk by all selected toolboxes and switch them off            
            for ii = 1:numel(toolbox)

                tb = toolbox{ii};

                if isfield(toolbox_states, tb) && ~toolbox_states.(tb)
                    warning([msgId ':toolbox_already_switched_off'],...
                            'Toolbox ''%s'' already switched off; ignoring.',...
                            tb);
                else
                    % Remove whole toolbox from path
                    toolbox_states.(tb) = false;
                    inds  = ~cellfun('isempty', ...
                                     strfind(paths, fullfile(matlabroot, 'toolbox', tb))); %#ok<STRCL1>
                    rmpath(paths{inds});
                end

            end


        case {'on' 'enable' 'restore'}

            switched = false;

            for ii = 1:numel(toolbox)

                tb = toolbox{ii};

                if ~isfield(toolbox_states, toolbox{ii})
                    warning([msgId ':toolbox_not_switched_off'],...
                            'Toolbox ''%s'' was not switched off; ignoring.',...
                            tb);
                else
                    switched = true;
                end

                % Just set toggle state
                toolbox_states.(tb) = true;

            end

            % Preserve path order:
            % - restore whole path
            % - then re-disable relevant toolboxes
            if switched

                newPaths = ~ismember(paths, toolbox_states.path);
                if ~any(newPaths)
                    % No new paths have been added
                    path( sprintf('%s;', toolbox_states.path{1:end-1}),...
                          toolbox_states.path{end} );
                    paths = toolbox_states.path;
                else
                    % TODO: wouldn't it be better to "simply" merge the paths?
                    warning([msgId ':new_paths_added'],[ ...
                            'New directories have been added to the path between consecutive ',...
                            '''on''/''off'' calls to %s. The path will be restored to that prior to ',...
                            'the first ''off'' call to %s, which will effectively remove these ',...
                            'new directories from the path.'],...
                            mfilename, mfilename);
                end

                toolboxes = fieldnames(toolbox_states);
                toolboxes = toolboxes(~strcmp(toolboxes, 'path'));

                for jj = 1:numel(toolboxes)
                    tb = toolboxes{jj};
                    if ~toolbox_states.(tb)
                        inds  = ~cellfun('isempty',...
                                         strfind(paths, fullfile(matlabroot, 'toolbox', tb))); %#ok<STRCL1>
                        rmpath(paths{inds});
                    end
                end

            end

    end

    %% Finish up
    % ====================================================

    % Save toggle states and previous paths
    setpref('toggleToolbox___',...
            'toolbox_states',...
            toolbox_states);

    % Make changes permanent when requested
    switch lower(permanent)
        case 'temporary'
            % noop; the default
        case 'permanent'
            savepath();
    end

    if ~restoremode
        varargout{1} = toolbox_states_out; end

    % Update toolbox cache
    rehash toolboxcache

end

function tb_name_map = get_tb_name_map()

    persistent tb_map
    if isempty(tb_map)

        disp('First call; collecting toolbox information. Please wait...');

        % Cellstring of all paths makes for easier work
        paths = regexp(path, pathsep, 'split');

        % Get list of toolbox directory names
        tbs = dir(fullfile(matlabroot, 'toolbox'));
        tbs = tbs(3:end);
        tb_dirnames = {tbs.name}';

        % Get the full toolbox names
        S(numel(tb_dirnames)) = struct('Name',    '',...
                                       'Version', '',...
                                       'Release', '',...
                                       'Date',    '');

        for ii = 1:numel(tb_dirnames)

            tb_dirname = tb_dirnames{ii};

            % Add toolbox (could have been removed from path, in which case
            % ver() will not find it)
            tb_dir = fullfile(matlabroot, 'toolbox', tb_dirname);
            inds = ~cellfun('isempty', ...
                            strfind(paths, tb_dir)); %#ok<STRCL1>

            if ~any(inds)
                addpath(genpath(tb_dir)); end

            % Get toolbox information via ver()
            % NOTE: (Rody Oldenhuis) 'fixpoint' has been renamed to 
            % 'fixedpoint' in an unknown MATLAB version, resulting in a
            % warning if you use the old name. Introduce some
            % version-specific code here: 
            if strcmpi(tb_dirname, 'fixpoint') && ~verLessThan('matlab', '9.1')
                % TODO: update to the first version actually giving the warning                                       
                tb_version = ver('fixedpoint');                
            else
                tb_version = ver(tb_dirname);
            end
            
            if ~isempty(tb_version)
                S(ii) = tb_version; end

        end

        tb_fullnames = {S.Name}';

        % Some dirs may not be toolboxes; slice those off
        tb_slice = ~cellfun('isempty', tb_fullnames);

        tb_fullnames = tb_fullnames(tb_slice);
        tb_dirnames  = tb_dirnames (tb_slice);

        % Collect terms
        tb_map = [tb_dirnames tb_fullnames];

        % Reset path
        path(sprintf('%s;', paths{1:end-1}), paths{end});

    end

    tb_name_map = tb_map;

end
