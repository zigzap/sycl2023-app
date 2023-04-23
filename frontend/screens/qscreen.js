export function show_qscreen(screen, task, submit, utils) {
    let invalid = false;
    let _isLoading = false;
    let _allQfinished = false;
    let _answers = {};
    let _taskBody = {};
    let _qidlist = [];
    let _markdownBody;
    let _msgPleaseAnswer = "";

    function showQ(qid, json) {
        let qtext = json.Question;
        let qtype = json.QType;
        switch (qtype) {
          case 'check_horizontal': {
              return HorizontalRadioQ(qid, qtext, json);
            }

          case 'check_vertical': {
              return VerticalRadioQ(qid, qtext, json);
            }

          // case 'number':
          //   {
          //     var minValue = json['min'];
          //     var maxValue = json['max'];
          //     return Container(
          //       padding: EdgeInsets.fromLTRB(
          //         50 * factor,
          //         10 * factor,
          //         50 * factor,
          //         10 * factor,
          //       ),
          //       child: NumberInput(
          //         qid: qid,
          //         questionText: qtext,
          //         onAnswer: _onAnswer,
          //         factor: factor,
          //         minValue: minValue,
          //         maxValue: maxValue,
          //       ),
          //     );
          //   }

          default: {
              // just text
              let converter = new showdown.Converter();
              let t = document.createElement("H1");
              t.innerHTML = converter.makeHtml(qtext);
              return t;
            }
        }
    }

    function VerticalRadioQ(qid, questionText, json) {
        let jsonOptions = json.options;
        let _groupvalue = " ";

        let col = document.createElement("DIV");
        col.classList.add("col");
        col.classList.add("qvert");

        if(questionText.length > 3) {
            let qtextrow = document.createElement("DIV");
            qtextrow.classList.add("row");
            let converter = new showdown.Converter();
            // qtextrow.innerHTML = converter.makeHtml('**' + questionText + '**');
            qtextrow.innerHTML = converter.makeHtml(questionText);
            col.appendChild(qtextrow);
        }

        // show all options
        // `json` contaons a list of options in property `options` in this case
        for(const option of jsonOptions) {
            let rrow = document.createElement("DIV");
            rrow.classList.add("row");
            rrow.classList.add("qvert_option");
            let radio = document.createElement("INPUT");
            radio.id = option;
            radio.type = "radio";
            radio.name = qid;
            radio.value = option;
            let rlabel = document.createElement("LABEL");
            rlabel.for = option;
            rlabel.innerHTML = option;

            radio.addEventListener('change', function() {
                _groupvalue = this.value;
                _onAnswer(qid, _groupvalue);
            });

            rrow.onclick = function() {
                let radio = document.getElementById(option);
                console.log("clicked", option);
                radio.checked = true;
                _groupvalue = option;
                _onAnswer(qid, _groupvalue);
            };
            rrow.appendChild(radio);
            rrow.appendChild(rlabel);
            col.appendChild(rrow);
        }
        return col;
    }

    function HorizontalRadioQ(qid, questionText, json) {
        let jsonOptions = json.options;
        let _groupvalue = " ";

        let _scaleLeft = json.scale_left;
        let _scaleRight = json.scale_right;
        let _showDividers = false;
        if (json.hasOwnProperty('show_dividers')) {
          _showDividers = json.show_dividers;
        }
        let _showOptionLabels = true;
        if (json.hasOwnProperty('show_option_labels')) {
          _showOptionLabels = json.show_option_labels;
        }

        let col = document.createElement("DIV");
        col.classList.add("qhoriz");

        if(_showDividers) { 
            let hr_1st = document.createElement("HR");
            col.appendChild(hr_1st);
        }

        if(questionText.length > 3) {
            let qtextrow = document.createElement("DIV");
            qtextrow.classList.add("row");
            let converter = new showdown.Converter();
            qtextrow.innerHTML = converter.makeHtml(questionText);
            col.appendChild(qtextrow);
        }

        let container = document.createElement("DIV");
        let table = document.createElement("TABLE");
        let row = document.createElement("TR");
        table.appendChild(row);
        container.appendChild(table);
        col.appendChild(container);

        let leftscalecol = document.createElement("TD");
        leftscalecol.classList.add("qhoriz_leftscale");
        // width is handled in css
        leftscalecol.innerHTML = _scaleLeft;
        row.appendChild(leftscalecol);

        // show all options
        // `json` contaons a list of options in property `options` in this case
        for(const option of jsonOptions) {
            let radio_col = document.createElement("TD");

            let radio = document.createElement("INPUT");
            radio.id = option;
            radio.type = "radio";
            radio.name = qid;
            radio.value = option;
            radio.addEventListener('change', function() {
                _groupvalue = this.value;
                _onAnswer(qid, _groupvalue);
            });
            radio_col.appendChild(radio);
            row.appendChild(radio_col);
        }

        let rightscalecol = document.createElement("TD");
        rightscalecol.innerHTML = _scaleRight;
        rightscalecol.classList.add("qhoriz_rightscale");
        row.appendChild(rightscalecol);


        //
        // labels
        //
        {
            let row = document.createElement("TR");
            table.appendChild(row);
            let leftscalecol = document.createElement("TD");
            // leftscalecol.innerHTML = _scaleLeft;
            row.appendChild(leftscalecol);

            // show all options
            // `json` contaons a list of options in property `options` in this case
            for(const option of jsonOptions) {
                let radio_col = document.createElement("TD");

                let radio = document.createElement("P");
                radio.for = option;
                if(_showOptionLabels) {
                    radio.innerHTML = option;
                }
                radio_col.appendChild(radio);
                row.appendChild(radio_col);
            }

            let rightscalecol = document.createElement("TD");
            // rightscalecol.innerHTML = _scaleRight;
            row.appendChild(rightscalecol);
        }

        if(false && _showDividers) { 
            let hr_last = document.createElement("HR");
            col.appendChild(hr_last);
        }
        return col;
    }

    function _onAnswer(key, value) {
        _answers[key] = value;
    }
    
    function _areAllQsAnswered() {
      // check if all QIDs are present in _answers
      var ret = true;
      for (var qid of _qidlist) {
        if (!_answers.hasOwnProperty(qid)) {
          ret = false;
        }
      }
      return ret;
    }

    function _submit() {
        // TODO `
        console.log("Qscreen _submit");
        _allQfinished = _areAllQsAnswered();
        if(!_allQfinished) {
            utils.showToast(_msgPleaseAnswer);
            return;
        }

        submit();
    }

    _taskBody = task.taskbody;
    _qidlist = Object.keys(_taskBody['questions']);
    _qidlist.sort();
    if (_taskBody.hasOwnProperty('shuffle_questions')) {
      let _doShuffle = _taskBody['shuffle_questions'];
      if (_doShuffle) {
        utils.shuffleArray(_qidlist);
      }
    }
    _markdownBody = null;
    if (_taskBody.hasOwnProperty('body')) {
      _markdownBody = _taskBody.body;
    }
    _msgPleaseAnswer = "Bitte beantworten Sie alle Fragen!";
    if (_taskBody.hasOwnProperty('please_answer_msg')) {
      _msgPleaseAnswer = _taskBody['please_answer_msg'];
    }
    utils.make_basic_screen(screen, task);
    screen.classList.add("q_screen");

    // if necessary, will be added later
    let toast = document.createElement("DIV");
    toast.classList.add("toast");
    let snackbar = document.createElement("DIV");
    snackbar.id = "snackbar";


    if(_markdownBody) {
        utils.show_markdown_body(screen, task, "#### " + _markdownBody);
    }
    console.log(_qidlist);
    for (const qid of _qidlist) {
        let el = showQ(qid, _taskBody['questions'][qid]);
        screen.appendChild(el);
    }
    utils.make_next_button(screen, task, _submit);
}


