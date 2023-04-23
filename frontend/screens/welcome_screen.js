export function show_welcome(screen, task, submit, utils) {
    utils.make_basic_screen(screen, task);
    screen.classList.add("welcome_screen");

    // if necessary, will be added later
    let toast = document.createElement("DIV");
    toast.classList.add("toast");

    let overlay = document.createElement("div");
    overlay.classList.add("overlay");
    document.getElementById("overlay").appendChild(overlay);

    utils.show_title(screen, task);
    utils.show_markdown_body(screen, task, task.taskbody.body);

    // all the datenschutz stuff and volunteering
    let _hasDatenschutz =
        task.taskbody.hasOwnProperty('data_protection_heading');
    let _hasAgreement =
        task.taskbody.hasOwnProperty('agreement_check_caption');
    let _datenschutzChecked = false;
    let _agreementChecked = false;
    let _showBottom = false;

    if (_hasDatenschutz || _hasAgreement) {
      _showBottom = true;
    }
    let _datenschutzButtonCaption = "Read data protection and privacy statement";
    let _msgPleaseCheckDataprotection =
        "Please agree to the data protection and privacy statement";
    let _msgPleaseCheckAgreement = "Bitte willigen Sie in die Teilnahme ein!";

    if (task.taskbody.hasOwnProperty('dataprotection_button')) {
      _datenschutzButtonCaption =
          task.taskbody['dataprotection_button'];
    }
    if (task.taskbody.hasOwnProperty('please_check_dataprotection_msg')) {
      _msgPleaseCheckDataprotection =
          task.taskbody['please_check_dataprotection_msg'];
    }
    if (task.taskbody.hasOwnProperty('please_check_agreement_msg')) {
      _msgPleaseCheckAgreement =
          task.taskbody['please_check_agreement_msg'];
    }

    if(_showBottom) {
        let row = document.createElement("div");
        row.classList.add("row");
        let col = document.createElement('div');
        col.classList.add("column");
        row.appendChild(col);

        let divider = document.createElement("hr");
        divider.classList.add("divider");
        col.appendChild(divider); // -- row

        if(_hasAgreement) {
            let agr_row = document.createElement("div");
            agr_row.classList.add("row");
            let lbl_agr = document.createElement("LABEL");
            lbl_agr.classList.add("agreement_check");
            lbl_agr.innerHTML = task.taskbody.agreement_check_caption;
            let chk_agr = document.createElement("INPUT");
            chk_agr.type = "checkbox";
            chk_agr.classList.add("checkbox");

            lbl_agr.onclick = function() {
                chk_agr.checked = !chk_agr.checked;
                _agreementChecked = chk_agr.checked;
            }

            chk_agr.onclick = function() {
                _agreementChecked = chk_agr.checked;
            }

            agr_row.appendChild(chk_agr);
            agr_row.appendChild(lbl_agr);
            col.appendChild(agr_row);
        }

        if(_hasDatenschutz) {
            let dschutz_row = document.createElement("div");
            dschutz_row.classList.add("row");
            let lbl_dschutz = document.createElement("LABEL");
            lbl_dschutz.classList.add("data_protection");
            lbl_dschutz.innerHTML = task.taskbody.data_protection_check_caption;
            let chk_dschutz = document.createElement("INPUT");
            chk_dschutz.type = "checkbox";
            chk_dschutz.classList.add("checkbox");

            lbl_dschutz.onclick = function() {
                chk_dschutz.checked = !chk_dschutz.checked;
                _datenschutzChecked = chk_dschutz.checked;
            }

            chk_dschutz.onclick = function() {
                _datenschutzChecked = chk_dschutz.checked;
            }

            dschutz_row.appendChild(chk_dschutz);
            dschutz_row.appendChild(lbl_dschutz);
            col.appendChild(dschutz_row);
        }

        screen.appendChild(row);
    }

    function pre_submit() {
        console.log("in pre_submit");

        if(_hasDatenschutz) {
            if(!_datenschutzChecked) {
                utils.showToast(_msgPleaseCheckDataprotection);
                console.log(_msgPleaseCheckDataprotection);
                return;
            }
        }

        if(_hasAgreement) {
            if(!_agreementChecked) {
                utils.showToast(_msgPleaseCheckAgreement);
                console.log(_msgPleaseCheckAgreement);
                return;
            }
        }

        submit();
    }

    if(_showBottom) {
        screen.appendChild(toast);

        let d = document.createElement("DIV");
        d.classList.add("next_div");

        let ds_bt = document.createElement("BUTTON");
        ds_bt.innerHTML = _datenschutzButtonCaption;
        ds_bt.classList.add("dsbutton");
        ds_bt.onclick = function() {
            show_datenschutz();
        }
        d.appendChild(ds_bt);

        let b = document.createElement("BUTTON");
        b.innerHTML = task.next_button;
        b.classList.add("nextbutton");
        b.onclick = function() {
            pre_submit();
        }
        d.appendChild(b);

        screen.appendChild(toast)
        screen.appendChild(d);
    } else {
        utils.make_next_button(screen, task, pre_submit);
    }

    function show_datenschutz() {
        overlay.innerHTML = "";
        let converter = new showdown.Converter();
        let overlay_text = document.createElement("P");
        let anywhere = "\n\n###Click anywhere to close this text\n\n";
        let t = anywhere + task.taskbody.data_protection_body + anywhere;
        overlay_text.innerHTML = converter.makeHtml(t);
        overlay_text.classList.add("overlay-text");
        overlay.appendChild(overlay_text);
        overlay.style.display="block";
        overlay.onclick = function() {
            if(overlay.style.display == "block") {
                overlay.style.display = "none";
            } 
        }
        console.log("block");
    }
}


