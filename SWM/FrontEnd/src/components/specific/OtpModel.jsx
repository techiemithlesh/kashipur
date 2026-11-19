import { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import axios from 'axios';
import toast from 'react-hot-toast';
import RequestOtpForm from './RequestOtpForm';
import ResetPasswordForm from './ResetPasswordForm';
import { modalVariants } from '../../utils/motionVariable';

const OtpModal = ({ onClose  }) => {
    const [email, setEmail] = useState('');
    const [otpRequested, setOtpRequested] = useState(false);
    const [isResending, setIsResending] = useState(false);
    const [resendSeconds, setResendSeconds] = useState(0);

    useEffect(() => {
      if (resendSeconds === 0) return;

      const timer = window.setTimeout(() => {
        setResendSeconds((seconds) => seconds - 1);
      }, 1000);

      return () => window.clearTimeout(timer);
    }, [resendSeconds]);

    const handleOtpRequested = (email) => {
      setEmail(email);
      setOtpRequested(true);
      setResendSeconds(60);
    };

  const handleResendOtp = async () => {
    if (isResending || resendSeconds > 0) return;

    setIsResending(true);
    try {
      const api = `${import.meta.env.VITE_REACT_APP_BACKEND_API}/api/forgot-password`;
      const { data } = await axios.post(api, { email });

      if (data.status) {
        setResendSeconds(60);
        toast.success(data.message || "A new code was sent.");
      } else {
        toast.error(data.message || "Could not resend the code.");
      }
    } catch (error) {
      toast.error(error.response?.data?.message || "Could not resend the code.");
    } finally {
      setIsResending(false);
    }
  };

  const countdown = `${Math.floor(resendSeconds / 60)}:${String(resendSeconds % 60).padStart(2, '0')}`;
  let resendLabel = 'Resend OTP';
  if (isResending) {
    resendLabel = 'Sending…';
  } else if (resendSeconds > 0) {
    resendLabel = `Resend OTP in ${countdown}`;
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/60 p-4">
      <motion.div
        role="dialog"
        aria-modal="true"
        aria-labelledby="password-recovery-title"
        className="relative max-h-full w-full max-w-md overflow-y-auto rounded-2xl bg-white p-6 shadow-xl sm:p-8"
        initial="hidden"
        animate="visible"
        exit="hidden"
        variants={modalVariants}
        transition={{ duration: 0.5 }}
      >
        <button
          type="button"
          onClick={onClose}
          aria-label="Close password recovery"
          className="absolute right-3 top-3 h-10 w-10 rounded-lg text-xl text-slate-600 hover:bg-slate-100"
        >
          ×
        </button>
        <h2 id="password-recovery-title" className="mb-4 pr-10 text-xl font-semibold">
          {otpRequested ? "Reset your password" : "Forgot your password?"}
        </h2>
        {otpRequested ? (
          <>
            <ResetPasswordForm email={email} />
            <button
              type="button"
              onClick={handleResendOtp}
              disabled={isResending || resendSeconds > 0}
              className="mt-4 text-sm font-semibold text-primary hover:underline disabled:opacity-50"
            >
              {resendLabel}
            </button>
          </>
        ) : (
          <RequestOtpForm onOtpRequested={handleOtpRequested} />
        )}
      </motion.div>
    </div>
  );
};

export default OtpModal;
