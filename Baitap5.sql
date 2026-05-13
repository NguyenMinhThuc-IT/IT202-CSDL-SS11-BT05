-- PHẦN A. THIẾT KẾ KIẾN TRÚC

/*
FLOW XỬ LÝ

Receive Request (patient_id, target_dept_id)
                |
                v
1. Kiểm tra Dept_ID có tồn tại?
   -> Không: trả lỗi "Khoa không tồn tại"
                |
                v
2. Kiểm tra bệnh nhân có lịch Completed?
   -> Có: trả lỗi "Từ chối: Bệnh nhân đã xuất viện"
                |
                v
3. Gọi procedure phụ FindAvailableBed()
   -> Không tìm thấy giường:
      trả lỗi "Từ chối: Khoa [Tên Khoa] đã hết giường"
                |
                v
4. START TRANSACTION
                |
                v
5. Giải phóng giường cũ (patient_id = NULL)
                |
                v
6. Gán bệnh nhân vào giường mới
                |
                v
7. COMMIT
                |
                v
8. Trả về new_bed_id + "Chuyển giường thành công"
*/


/*
THIẾT KẾ GIAO TIẾP

Procedure phụ:
FindAvailableBed(
    IN  p_dept_id INT,
    OUT p_bed_id INT
)

Procedure Master:
TransferPatientBed(
    IN  p_patient_id INT,
    IN  p_target_dept_id INT,
    OUT p_new_bed_id INT,
    OUT p_message VARCHAR(255)
)

=> Procedure Master dùng biến local và OUT parameter để
   nhận kết quả từ procedure phụ.
*/


-- PHẦN B. PROCEDURE PHỤ: FINDAVAILABLEBED

DROP PROCEDURE IF EXISTS FindAvailableBed;

DELIMITER //

CREATE PROCEDURE FindAvailableBed(
    IN p_dept_id INT,
    OUT p_bed_id INT
)
BEGIN
    SELECT bed_id
    INTO p_bed_id
    FROM Beds
    WHERE dept_id = p_dept_id
      AND patient_id IS NULL
    LIMIT 1;
END //

DELIMITER ;


-- PHẦN C. PROCEDURE MASTER: TRANSFERPATIENTBED

DROP PROCEDURE IF EXISTS TransferPatientBed;

DELIMITER //

CREATE PROCEDURE TransferPatientBed(
    IN p_patient_id INT,
    IN p_target_dept_id INT,
    OUT p_new_bed_id INT,
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE v_current_bed_id INT;
    DECLARE v_available_bed_id INT;
    DECLARE v_dept_name VARCHAR(100);
    DECLARE v_completed_count INT DEFAULT 0;

    -- Mặc định
    SET p_new_bed_id = NULL;

    -- 1. Kiểm tra khoa có tồn tại
    SELECT dept_name
    INTO v_dept_name
    FROM Departments
    WHERE dept_id = p_target_dept_id;

    IF v_dept_name IS NULL THEN
        SET p_message = 'Từ chối: Khoa không tồn tại';

    ELSE
        -- 2. Kiểm tra bệnh nhân đã xuất viện chưa
        SELECT COUNT(*)
        INTO v_completed_count
        FROM Appointments
        WHERE patient_id = p_patient_id
          AND status = 'Completed';

        IF v_completed_count > 0 THEN
            SET p_message = 'Từ chối: Bệnh nhân đã xuất viện';

        ELSE
            -- 3. Tìm giường trống bằng procedure phụ
            CALL FindAvailableBed(p_target_dept_id, v_available_bed_id);

            IF v_available_bed_id IS NULL THEN
                SET p_message = CONCAT(
                    'Từ chối: Khoa ',
                    v_dept_name,
                    ' đã hết giường'
                );

            ELSE
                -- 4. Lấy giường hiện tại
                SELECT bed_id
                INTO v_current_bed_id
                FROM Beds
                WHERE patient_id = p_patient_id
                LIMIT 1;

                START TRANSACTION;

                -- 5. Giải phóng giường cũ
                UPDATE Beds
                SET patient_id = NULL
                WHERE bed_id = v_current_bed_id;

                -- 6. Gán vào giường mới
                UPDATE Beds
                SET patient_id = p_patient_id
                WHERE bed_id = v_available_bed_id;

                COMMIT;

                -- 7. Trả kết quả
                SET p_new_bed_id = v_available_bed_id;
                SET p_message = 'Chuyển giường thành công';
            END IF;
        END IF;
    END IF;
END //

DELIMITER ;

-- PHẦN D. KIỂM THỬ

-- 1. Chuyển khoa thành công
-- Bệnh nhân 1 từ khoa 1 sang khoa 2 (giường 201 đang trống)
CALL TransferPatientBed(1, 2, @new_bed, @msg);
SELECT @new_bed AS new_bed_id, @msg AS message;

-- 2. Bẫy hết giường trống
-- Khoa 3 hiện không có giường trống
CALL TransferPatientBed(1, 3, @new_bed, @msg);
SELECT @new_bed AS new_bed_id, @msg AS message;

-- 3. Bẫy bệnh nhân đã xuất viện
-- Patient 2 có appointment 105 với status Completed
CALL TransferPatientBed(2, 1, @new_bed, @msg);
SELECT @new_bed AS new_bed_id, @msg AS message;

-- 4. Khoa không tồn tại
CALL TransferPatientBed(1, 999, @new_bed, @msg);
SELECT @new_bed AS new_bed_id, @msg AS message;