import { useState } from 'react';
import { motion } from 'framer-motion';
import RequestOtpForm from './RequestOtpForm';
import ResetPasswordForm from './ResetPasswordForm';
import { modalVariants } from '../../utils/motionVariable';

const OtpModal = ({ onClose  }) => {
    const [email, setEmail] = useState('');
    const [otpRequested, setOtpRequested] = useState(false);
  
    const handleOtpRequested = (email) => {
      setEmail(email);
      setOtpRequested(true);
    };


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
          <ResetPasswordForm email={email} />
        ) : (
          <RequestOtpForm onOtpRequested={handleOtpRequested} />
        )}
      </motion.div>
    </div>
  );
};

export default OtpModal;
