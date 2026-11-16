// Please see documentation at https://docs.microsoft.com/aspnet/core/client-side/bundling-and-minification
// for details on configuring this project to bundle and minify static web assets.

// Write your Javascript code.

var ChangedInputArray = [];
var pblAccContactList = [2, 3, 4, 5, 6];
var pblIntContactList = [2, 3, 4, 5, 6];
var pblInFieldChange = false;
var hideprogress = false;
var refreshpage = false;
function st(s) {
    if (s == null)
        return null;
    return s.toString().replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#x27;').replace(/\//g, '&#x2F;');
}
function strDecode(str) {
    return str == null ? null : he.decode(str);
};

$(document).on({
    ajaxStart: function () { if (!hideprogress) $("body").addClass("loading"); },
    ajaxStop: function () { if (!refreshpage) $("body").removeClass("loading"); }
});

function SuspensionDataSerialization() {
    var check = 0;
    var Details = []
    $('#tblViolationDetails > tbody  > tr').each(function (index, tr) {
        var rowId = tr.getAttribute('row-id');

        if ($('#AS_' + rowId).val() == 3 && $('#N_' + rowId).val() == "") {
            SetInputColor($('#N_' + rowId), '#ff0000');
            $('#N_' + rowId).focus();
            check = -1;
            return;
        }
        if (($('#AS_' + rowId).val() == 4) && ($('#R_' + rowId).val() == "" && $('#HPR_' + rowId).val() == "")) {
            bootbox.alert({ title: '<div class="row"><div class="col-1"><img src="/img/error.png" width="20" style="position:absolute; padding-top:2px"/></div><div class="col">Error</div></div>', closeButton: false, centerVertical: true, message: '<h5>Аn error occurred while saving data: Missing reason!</h5>' });
            check = -1;
            $('#R_' + rowId).focus();
            return;
        }
        if (tr.getAttribute('data-changed') == 1)
            Details.push({
                Id: rowId,
                SampleProof: $('#SP_' + rowId).is(":checked"),
                ApprovalStatus_id: $('#AS_' + rowId).val(),
                Notes: $('#N_' + rowId).val(),
                Reason_id: $('#R_' + rowId).attr('reason_id') == "" ? null : $('#R_' + rowId).attr('reason_id'),
                HPReason_id: $('#HPR_' + rowId).attr('reason_id') == "" ? null : $('#HPR_' + rowId).attr('reason_id'),
                Changed: tr.getAttribute('data-changed') == 1
            });
    });
    if (check == -1)
        return check;

    if (($('#ApprovalStatus_id').val() == 3 || $('#ApprovalStatus_id').val() == 4) && $('#Notes').val() == "") {
        SetInputColor($('#Notes'), '#ff0000');
        $('#Notes').focus();
        return -1;
    }
    var lcNotification = {
        Id: NotificationId,
        Contact1: $('#Contact1').val() == undefined ? "" : $('#Contact1').val(),
        Contact2: $('#Contact2').val() == undefined ? "" : $('#Contact2').val(),
        Contact3: $('#Contact3').val() == undefined ? "" : $('#Contact3').val(),
        Contact4: $('#Contact4').val() == undefined ? "" : $('#Contact4').val(),
        Contact5: $('#Contact5').val() == undefined ? "" : $('#Contact5').val(),
        Contact6: $('#Contact6').val() == undefined ? "" : $('#Contact6').val(),
        Email1: $('#Email1').val() == undefined ? "" : $('#Email1').val(),
        Email2: $('#Email2').val() == undefined ? "" : $('#Email2').val(),
        Email3: $('#Email3').val() == undefined ? "" : $('#Email3').val(),
        Email4: $('#Email4').val() == undefined ? "" : $('#Email4').val(),
        Email5: $('#Email5').val() == undefined ? "" : $('#Email5').val(),
        Email6: $('#Email6').val() == undefined ? "" : $('#Email6').val(),
        PreviousDeliveryDate: $('#dtpPreviousDeliveryDate').val() == '' ? null : $('#dtpPreviousDeliveryDate').val(),
        PenaltyPeriodStart: $('#dtpPenaltyPeriodStart').val() == '' ? null : $('#dtpPenaltyPeriodStart').val(),
        PenaltyPeriodEnd: $('#dtpPenaltyPeriodEnd').val() == '' ? null : $('#dtpPenaltyPeriodEnd').val(),
        SuspensionStart: $('#dtpSuspensionStart').val() == '' ? null : $('#dtpSuspensionStart').val(),
        SuspensionEnd: $('#dtpSuspensionEnd').val() == '' ? null : $('#dtpSuspensionEnd').val(),
        Address: $('#Address').val(),
        City: $('#Address2').attr('data-city'),
        State_id: $('#Address2').attr('data-state') == '' ? null : $('#Address2').attr('data-state'),
        Zip: $('#Address2').attr('data-zip'),
        ApprovalStatus_id: $('#ApprovalStatus_id').val(),
        Notes: $('#Notes').val(),
        VisibleForHP: $('#VisibleForHP').length >= 1 ? ($('#VisibleForHP').prop("checked") == true ? 1 : 0) : -1,
        Details: Details
    }
    return lcNotification;
}

function ViolationDataSerialization(inChangedRow = "") {
    var check = 0;
    if (inChangedRow == "") 
        if (($('#ApprovalStatus_id').val() == 3 || $('#ApprovalStatus_id').val() == 4) && $('#Notes').val() == "") {
            SetInputColor($('#Notes'), '#ff0000');
            $('#Notes').focus();
            return -1;
        }
    
    var Details = []
    $('#tblViolationDetails > tbody  > tr').each(function (index, tr) {
        var rowId = tr.getAttribute('row-id');

        if ($('#AS_' + rowId).val() == 3 && $('#N_' + rowId).val() == "") {
            SetInputColor($('#N_' + rowId), '#ff0000');
            $('#N_' + rowId).focus();
            check = -1;
        }
        if (($('#AS_' + rowId).val() == 4) && ($('#R_' + rowId).val() == "" && $('#HPR_' + rowId).val() == "")) {
            bootbox.alert({ title: '<div class="row"><div class="col-1"><img src="/img/error.png" width="20" style="position:absolute; padding-top:2px"/></div><div class="col">Error</div></div>', closeButton: false, centerVertical: true, message: '<h5>Аn error occurred while saving data: Missing reason!</h5>' });
            check = -1;
            $('#R_' + rowId).focus();
            return false;
        }
        Details.push({
            Id: rowId,
            ApprovalStatus_id: $('#AS_' + rowId).val(),
            Alternative_Percent_Amount: $('#APA_' + rowId).val() == undefined ? null : $('#APA_' + rowId).val(),
            Notes: $('#N_' + rowId).val(),
            Reason_id: $('#R_' + rowId).attr('reason_id') == undefined || $('#R_' + rowId).attr('reason_id') == "" ? null : $('#R_' + rowId).attr('reason_id'),
            HPReason_id: $('#HPR_' + rowId).attr('reason_id') == undefined || $('#HPR_' + rowId).attr('reason_id') == "" ? null : $('#HPR_' + rowId).attr('reason_id'),
            Changed: tr.getAttribute('data-changed') == 1
        });
    });
    if (check == -1)
        return check;

    var lcNotification = {
        Id: NotificationId,
        Contact1: $('#Contact1').val() == undefined ? null : $('#Contact1').val(),
        Contact2: $('#Contact2').val() == undefined ? null : $('#Contact2').val(),
        Contact3: $('#Contact3').val() == undefined ? null : $('#Contact3').val(),
        Contact4: $('#Contact4').val() == undefined ? null : $('#Contact4').val(),
        Contact5: $('#Contact5').val() == undefined ? null : $('#Contact5').val(),
        Contact6: $('#Contact6').val() == undefined ? null : $('#Contact6').val(),
        Email1: $('#Email1').val() == undefined ? null : $('#Email1').val(),
        Email2: $('#Email2').val() == undefined ? null : $('#Email2').val(),
        Email3: $('#Email3').val() == undefined ? null : $('#Email3').val(),
        Email4: $('#Email4').val() == undefined ? null : $('#Email4').val(),
        Email5: $('#Email5').val() == undefined ? null : $('#Email5').val(),
        Email6: $('#Email6').val() == undefined ? null : $('#Email6').val(),
        Address: $('#Address').val(),
        City: $('#Address2').attr('data-city'),
        State_id: $('#Address2').attr('data-state') == '' ? null : $('#Address2').attr('data-state'),
        Zip: $('#Address2').attr('data-zip'),
        ApprovalStatus_id: $('#ApprovalStatus_id').val(),
        Notes: $('#Notes').val(),
        VisibleForHP: $('#VisibleForHP').length >= 1 ? ($('#VisibleForHP').prop("checked") == true ? 1 : 0) : -1,
        SuppliesAlternativePercent: $('#SAP').val() == undefined ? "" : $('#SAP').val(),
        Details: Details
    }
    return lcNotification;
}

function AddMailManu(inAccOrInt, inIndex = 0, inVale = '', onLoad = 0) {
    if (inAccOrInt == 1) {
        var lcLastContact;
        if (pblIntContactList.length > 0) {
            var lcId = '';
            if (inIndex != 0) {
                if (!pblIntContactList.includes(inIndex))
                    return
                else
                    lcId = inIndex;
            }
            else
                lcId = pblIntContactList[0];

            var lcNewContact = '<dl class="row row-10" id="Email' + lcId + 'Row">' +
                '<dt class="collabel"></dt><dd><div class="row"><div class="col" style="padding-right:5px">' +
                '<input id="Email' + lcId + '" readonly type="text" isinternal="1" class="form-control form-control-sm" placeholder="Enter valid E-Mail" value="' + inVale + '" onchange="OnChange();"></div>' +
                '<div class="col-1" style="padding-left:0px;padding-top:3px">' +
                '<img id="imgEmail' + lcId + '"src="/img/edit.png" style = "width: 22px;cursor: pointer;" href="#" data-id="Email' + lcId + '" data-toggle="modal" data-target="#EditContactDlg" title="Edit" />' +
                '</div><div class="col-1" style="padding-left:3px;padding-top:3px">'+
                '<img src="/img/delete2.png" style="width: 22px;cursor: pointer;" href="#" data-id="Email' + lcId + '" title="Remove" onclick="RemoveContact(this);" />'+
                '</div></div></dd></dl>';

            $('#intContacts').children().each(function () {
                if (this.id.startsWith('Email'))
                    lcLastContact = this.id;
            });

            $('#' + lcLastContact).after(lcNewContact);
            if (onLoad != 1)
                $('#imgEmail' + lcId).click();
            //$('#Email' + lcId).focus();

            pblIntContactList = pblIntContactList.filter(e => e !== lcId)
        }

        if (pblIntContactList.length == 0)
            $('#lbAddEMail').remove();
    }
    else {
        var lcLastContact;
        if (pblAccContactList.length > 0) {
            var lcId = '';
            if (inIndex != 0) {
                if (!pblAccContactList.includes(inIndex))
                    return
                else
                    lcId = inIndex;
            }
            else
                lcId = pblAccContactList[0];
            
            var lcNewContact = '<dl class="row row-10" id="Contact' + lcId + 'Row">' +
                '<dt class="collabel"></dt><dd><div class="row"><div class="col" style="padding-right:5px">' +
                '<input id="Contact' + lcId + '" readonly type="text" isinternal="0" class="form-control form-control-sm" placeholder="Enter valid E-Mail" value="' + inVale + '" onchange="OnChange();"></div>' +
                '<div class="col-1" style="padding-left:0px;padding-top:3px">' +
                '<img id="imgContact' + lcId + '"src = "/img/edit.png" style = "width: 22px;cursor: pointer;" href="#" data-id="Contact' + lcId + '" data-toggle="modal" data-target="#EditContactDlg" title="Edit" />'+
                '</div><div class="col-1" style="padding-left:3px;padding-top:3px">'+
                '<img src="/img/delete2.png" style="width: 22px;cursor: pointer;" href="#" data-id="Contact' + lcId + '" title="Remove" onclick="RemoveContact(this);" />'+
                '</div></div></dd></dl>';
                        
            $('#accContacts').children().each(function () {
                if (this.id.startsWith('Contact'))
                    lcLastContact = this.id;
            });

            $('#' + lcLastContact).after(lcNewContact);
            if (onLoad != 1)
                $('#imgContact' + lcId).click();
            //$('#Contact' + lcId).focus();

            pblAccContactList = pblAccContactList.filter(e => e !== lcId)
        }
        if (pblAccContactList.length == 0)
            $('#lbAddContact').remove();
    }
}

function SetInputColor(inputId, Color) {
    $(inputId).attr("style", 'border-color:' + Color + '; background-color: #f0fbff');
};

function NumberWithCommas(inputNum, inRoundUp="") {
    if (inRoundUp.toString() == "")
        inRoundUp = 2
    try {
        if (isNaN(inputNum) || inputNum == null || inputNum == 0)
            return '-'
        else
            return inputNum.toFixed(inRoundUp).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    }
    catch (err) {
        return '-'
    }
}

function StrTrunc(str, max, add) {
    add = add || '...';
    return (typeof str === 'string' && str.length > max ? str.substring(0, max) + add : str);
};

function inputLineOnKeyPress(input) {
    var keycode = event.keyCode;
    var valid =
        (keycode > 47 && keycode < 58) || // number keys
        keycode == 32 || keycode == 13 || // spacebar & return key(s) (if you want to allow carriage returns)
        (keycode > 64 && keycode < 91) || // letter keys
        (keycode > 95 && keycode < 112) || // numpad keys
        (keycode > 185 && keycode < 193) || // ;=,-./` (in order)
        (keycode > 218 && keycode < 223);   // [\]' (in order)
    if (!valid)
        return;

    var val = Number(input.value);

    if (isNaN(val) || val < 0 || (input.id.includes('disc_inp_') && val > 100))
        SetInputColor('#' + input.id, '#ff0000');
    else
        SetInputColor('#' + input.id, '#0026ff');

    if (!ChangedInputArray.includes(input))
        ChangedInputArray.push(input);
};

function LandingPageDataSerialization() {
    var check = 0;
    var lcNotification = []
    $('#tbl_notifications > tbody  > tr[data-changed="1"]').each(function (index, tr) {
        var rowId = tr.getAttribute('id');

        if (($('#AS_' + rowId).val() == 3 || $('#AS_' + rowId).val() == 4) && $('#N_' + rowId).val() == "") {
            SetInputColor($('#N_' + rowId), '#ff0000');
            if (check != -1)
                $('#N_' + rowId).focus();
            check = -1;
            return;
        }
        lcNotification.push({
            Id: rowId,
            ApprovalStatus_id: $('#AS_' + rowId).val(),
            Notes: $('#N_' + rowId).val()
        });
    });
    if (check == -1)
        return check;
    else
        return lcNotification;
}

function OnChange() {
    pblInFieldChange = true;
    $('#btnAdd').attr('disabled', 'disabled');
}

function LineFieldChange(input) {
    OnChange();
    lcId = $(input).attr('row-id');
    $('#tr_' + lcId).attr('data-changed', 1);

    if (input.id == 'AS_' + lcId && $('#AS_' + lcId).val() == '2' && ($('#R_' + lcId).val() != null || $('#R_' + lcId).val() != null)) {
        $('#R_' + lcId).val('');
        $('#HPR_' + lcId).val('');
        $('#R_' + lcId).attr('reason_id','');
        $('#HPR_' + lcId).attr('reason_id', '');
        $('.selectpicker').selectpicker('refresh');
    }

    if ((input.id == 'R_' + lcId && $('#R_' + lcId).val() != '' || input.id == 'HPR_' + lcId && $('#HPR_' + lcId).val() != '') && $('#AS_' + lcId).val() == '2' && ($('#R_' + lcId).val() != null || $('#HPR_' + lcId).val() != null)) {
        $('#AS_' + lcId).val('4');
        $('.selectpicker').selectpicker('refresh');
    }

    if (input.id == 'APA_' + lcId) {
        if ($('#APA_' + lcId).val() == '') {
            $('#AP_' + lcId).text('-');
            $('#AP_' + lcId).attr('value', '0');
        }
        else {
            $('#AP_' + lcId).text(NumberWithCommas(($('#APA_' + lcId).val() / 100) * $('#APA_' + lcId).attr('totalpenalty'),0));
            $('#AP_' + lcId).attr('value',($('#APA_' + lcId).val() / 100) * $('#APA_' + lcId).attr('totalpenalty'));
        }
    } 
    
}

$('#EditContactDlg').on('show.bs.modal', function (e) {
    $('.modalTextInput').val('');
    let id = $(e.relatedTarget).data('id');
    lcContact = $('#' + id).val();
    if ($('#' + id).attr('isinternal') == 1) {
        lcName = '';
        lceMail = lcContact;
        $('#edContactName').attr('hidden', 'hidden');
        $('#lbContactName').attr('hidden', 'hidden');
    }
    else {
        $('#edContactName').removeAttr('hidden');
        $('#lbContactName').removeAttr('hidden');
        lcName = lcContact.lastIndexOf("(") == -1 ? "" : lcContact.substring(0, lcContact.lastIndexOf("("));
        lceMail = lcContact.lastIndexOf("(") == -1 ? lcContact : lcContact.substring(lcContact.lastIndexOf("(") + 1, lcContact.length - 1);
    }
    $('#edContactName').val(lcName);
    $('#edContacteMail').val(lceMail);
    $('#btnOk').data('id', id);
    $('#btnOk').data('isinternal', $('#' + id).attr('isinternal'));
})

$('#btnOk').on('click', function () {
    let id = $(this).data('id');
    if ($(this).data('isinternal') == 1) {
        $('#' + id).val($('#edContacteMail').val())
    }
    else {
        if ($('#edContactName').val() != "" && $('#edContacteMail').val().toString() != "")
            $('#' + id).val($('#edContactName').val() + '(' + $('#edContacteMail').val() + ')');
        else
            $('#' + id).val($('#edContactName').val() + $('#edContacteMail').val());
    }
    $('#EditContactDlg').modal('toggle');
    OnChange(id);
})

$('#EditAddressDlg').on('show.bs.modal', function (e) {
    $('.modalTextInput').val('');
    let id = $(e.relatedTarget).data('id');
    lcAddress = $('#' + id).val();
    lcCity = $('#' + id + '2').attr('data-city');
    lcState = $('#' + id + '2').attr('data-state');
    lcZIP = $('#' + id + '2').attr('data-zip');
    $('#edAddress').val(lcAddress);
    $('#edCity').val(lcCity);
    $('#edState').val(lcState);
    $('#edZIP').val(lcZIP);
    $('#addressbtnOk').data('id', id);
    $('.selectpicker').selectpicker('refresh');
})

$('#addressbtnOk').on('click', function () {
    let id = $(this).data('id');

    $('#' + id).val($('#edAddress').val());

    $('#' + id + '2').attr('data-city', $('#edCity').val());
    $('#' + id + '2').attr('data-state', $('#edState').val());
    $('#' + id + '2').attr('data-zip', $('#edZIP').val());
    $('#' + id + '2').val(($('#edCity').val() == '' ? '' : $('#edCity').val() + ', ') +
                          ($('#edState option:selected').text() == '' ? '' : $('#edState option:selected').text() + ' ') +
                           $('#edZIP').val());

    $('#EditAddressDlg').modal('toggle');
    OnChange(id);
})

function CreateStatusButtons(ShowVisibleForHP, VisibleForHP) {
    if (ShowVisibleForHP == 1) {
        $('#complianceSummaryHolder').append('<dl class="row row-10">' +
            '<dt class="collabel">Visible for HP</dt>' +
            '<dd>' +
            '<div style="width:153px">' +
            '<div class="custom-control custom-checkbox custom-control-inline form-control-sm border-0" style="padding:0px;margine-top:0px;margine-bottom:0px">' +
            '<input type="checkbox"' + (VisibleForHP == 1 ? ' checked' : '') + ' class="custom-control-input" id="VisibleForHP" name="VisibleForHP" onchange="OnChange();"/>' +
            '<label class="custom-control-label-datatable" for="VisibleForHP"></label>' +
            '</div>' +
            '</div></dd></dl>');
    }
}

function RemoveContact(e) {
    $('#' + e.getAttribute('data-id')).val('');
    OnChange();
};

function RemoveAddress(e) {
    $('#Address').val('');
    $('#Address2').val('');
    $('#Address2').attr('data-city', '');
    $('#Address2').attr('data-state', '');
    $('#Address2').attr('data-zip', '');
    OnChange();
};

function getSunday(inDate) {
    inDate = new Date(inDate);
    return new Date(inDate.setDate(inDate.getDate() - inDate.getUTCDay())).toISOString().slice(0, 10);
}

//Reason Select
function LoadReasons(e, reasonOptions) {
    $('#reasonsList').empty();
    if (reasonOptions == 1)
        pblHPReason.forEach(function (item) {
            $('#reasonsList').append('<li class="list-group-item list-group-item-action' + ($(e).attr('reason_id') == item.id ? ' list-group-item-primary' : '') + '" style="border:none;cursor:pointer" value="' + item.id + '" onclick="SelectReason(\'' + ($(e).attr('id')) + '\',' + ($(e).attr('row-id')) + ',' + item.id + ',\'' + item.options + '\');">' + item.options + '</li>');
        });
    else
        pblReason.forEach(function (item) {
            $('#reasonsList').append('<li class="list-group-item list-group-item-action' + ($(e).attr('reason_id') == item.id ? ' list-group-item-primary' : '') + '" style="border:none;cursor:pointer" value="' + item.id + '" onclick="SelectReason(\'' + ($(e).attr('id')) + '\',' + ($(e).attr('row-id')) + ',' + item.id + ',\'' + item.options + '\');">' + item.options + '</li>');
        });
    $('#EditReasonDlg').modal().show();
}

$('#EditReasonDlg').on('show.bs.modal', function () {
    setTimeout(function () {
        $('#searchReason').focus();
    }, 500);
})

$("#searchReason").on("keyup", function () {
    var value = $(this).val().toLowerCase();
    $("#reasonsList li").filter(function () {
        $(this).toggle($(this).text().toLowerCase().indexOf(value) > -1)
    });
});

function SelectReason(caller_id, row_id, item_id, item_option) {
    $('#' + caller_id).val(item_option);
    $('#' + caller_id).attr('reason_id', item_id);
    LineFieldChange(document.getElementById(caller_id))
    $('#EditReasonDlg').modal('toggle');
}