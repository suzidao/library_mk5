$(document).ready(function(){

    // Hide form, clear game barcode field on cancel click.
    $('#g-form-cancel').click(function(){
        $('#g-form').modal('hide');
        gameBarcode(true);
    });

    // Make a call to /attendee/status when a new barcode is entered.
    $('#new-g-barcode').change(function(){
        var barcode_val = $(this).val();

        if(!bc_regex.test(barcode_val)){
            $.notify('Invalid barcode format! Format should be like TTL####TT.', 'warning', 3000);
            $(this).val('');
            return;
        }
        gameBarcode(false);

        $.get('/game/status', { barcode: barcode_val }).success(function(response){
            $.get('/game/display', { barcode: barcode_val, message: 'Game already exists!' }, null, 'script');
            gameBarcode(true);
        }).error(function(response){
            if(response.status == 400){
                $('#g-form').modal();
            }else{
                $.notify(DEFAULT_ERROR, 'danger');
                gameBarcode(true);
            }
        });
    }).on('input', function(){
        $('#g-name').html('');
    });

    // Submit new game information. On success, hide form and display new info.
    $('#g-form-save').click(function(){
        var data = $('#g-form').find('input').serializeArray(),
            barcode_val = $('#new-g-barcode').val();
        data.push({
            name: 'barcode',
            value: barcode_val
        });
        $('#g-form').find('input').parent().removeClass('has-error').find('.glyphicon').hide();
        $.post('/game/new', data).success(function(response){
            if(response.game){
                $('#g-form').modal('hide');
                $.get('/game/display', { barcode: barcode_val, message: 'Game successfully added!' }, null, 'script');
                gameBarcode(true);
            }else{
                // got errors
                $.each(response.errors, function(k, v){
                    var input = $('[name="' + k + '"]');

                    input.parent().addClass('has-error');
                    input.siblings('.glyphicon').show();
                });
            }
        }).error(function(){

        });
    });

    // Clear all attendee form fields when the form is hidden.
    $('#g-form').on('hidden.bs.modal', function(){
        $('#g-form').find('input').val('').prop('checked', false);
    }).on('shown.bs.modal', function(){
        $('#g-form').find('[name="title"]').focus();
    });

});

function gameBarcode(bool){
    var barcode = $('#new-g-barcode');

    barcode.prop('disabled', !bool);
    if(bool){
        barcode.val('').focus();
    }
}